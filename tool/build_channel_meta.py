#!/usr/bin/env python3
"""Build assets/data/channel_meta.json from the iptv-org channel database.

The playlists (iptv-org/iptv streams/in.m3u and the movies, series and sports
category lists) carry little more than a tvg-id and a name per stream. The app
looks every tvg-id up in this file to sort channels into genres, filter by
language and show logos.

Usage: python3 tool/build_channel_meta.py [--country IN] [--playlist URL]

Every channel from the given countries is included, plus every channel the
given playlists mention (default: the playlists in data/streams.csv).
"""

import argparse
import csv
import io
import json
import pathlib
import re
import urllib.request

DATABASE = 'https://raw.githubusercontent.com/iptv-org/database/master/data/'
# The playlists in data/streams.csv.
PLAYLISTS = [
    'https://raw.githubusercontent.com/iptv-org/iptv/master/streams/in.m3u',
    'https://raw.githubusercontent.com/iptv-org/iptv/gh-pages/categories/movies.m3u',
    'https://raw.githubusercontent.com/iptv-org/iptv/gh-pages/categories/series.m3u',
    'https://raw.githubusercontent.com/iptv-org/iptv/gh-pages/categories/sports.m3u',
]
OUTPUT = pathlib.Path(__file__).resolve().parent.parent / 'assets/data/channel_meta.json'

# Image.network cannot draw SVG, so prefer bitmap logos.
LOGO_FORMATS = {'PNG': 0, 'WebP': 1, 'JPEG': 2, 'GIF': 3}


def fetch_csv(name):
    with urllib.request.urlopen(DATABASE + name, timeout=120) as response:
        return list(csv.DictReader(io.TextIOWrapper(response, encoding='utf-8')))


def playlist_ids(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        text = response.read().decode('utf-8', 'replace')
    return {tvg_id.split('@')[0] for tvg_id in re.findall(r'tvg-id="([^"]+)"', text)}


def pick_logo(logos):
    def score(logo):
        return (
            logo['in_use'] != 'TRUE',
            logo['feed'] != '',
            LOGO_FORMATS.get(logo['format'], 9),
            -int(logo['width'] or 0),
        )

    usable = [l for l in logos if l['format'] in LOGO_FORMATS and l['url']]
    return min(usable, key=score)['url'] if usable else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--country', action='append', default=None,
                        help='ISO country code to include (repeatable, default IN)')
    parser.add_argument('--playlist', action='append', default=None,
                        help='M3U playlist whose channels to include (repeatable, default: the app playlists)')
    args = parser.parse_args()
    countries = set(args.country or ['IN'])
    listed = set()
    for url in args.playlist or PLAYLISTS:
        listed |= playlist_ids(url)

    languages = {r['code']: r['name'] for r in fetch_csv('languages.csv')}
    channels = [
        r for r in fetch_csv('channels.csv')
        if r['is_nsfw'] != 'TRUE'
        and (r['id'] in listed or (r['country'] in countries and not r['closed']))
    ]
    wanted = {c['id'] for c in channels}

    feed_languages = {}
    for feed in fetch_csv('feeds.csv'):
        if feed['channel'] in wanted:
            codes = feed_languages.setdefault(feed['channel'], [])
            for code in feed['languages'].split(';'):
                if code and code not in codes:
                    codes.append(code)

    logos = {}
    for logo in fetch_csv('logos.csv'):
        if logo['channel'] in wanted:
            logos.setdefault(logo['channel'], []).append(logo)

    meta = {}
    for channel in sorted(channels, key=lambda c: c['id']):
        entry = {}
        if channel['categories']:
            entry['c'] = channel['categories'].split(';')
        names = [languages.get(code, code) for code in feed_languages.get(channel['id'], [])]
        if names:
            entry['lang'] = [n.replace(' (macrolanguage)', '') for n in names]
        logo = pick_logo(logos.get(channel['id'], []))
        if logo:
            entry['l'] = logo
        if entry:
            meta[channel['id']] = entry

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(meta, ensure_ascii=False, separators=(',', ':'), sort_keys=True) + '\n',
                      encoding='utf-8')
    print(f'Wrote {len(meta)} channels to {OUTPUT}')


if __name__ == '__main__':
    main()
