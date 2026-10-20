import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/channel.dart';
import '../model/channel_catalog.dart';
import '../model/genre.dart';
import '../model/stream_source.dart';
import '../provider/channels_provider.dart';
import '../services/device.dart';
import '../services/library_store.dart';
import '../widgets/browse_bars.dart';
import '../widgets/channel_tile.dart';
import 'player.dart';
import 'search.dart';

/// Tabs of the genre bar besides the genres themselves.
enum _Special { home, favourites }

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const _playlistKey = 'playlist';
  static const _languageKey = 'language';

  final ChannelsProvider channelsProvider = ChannelsProvider();
  final LibraryStore library = LibraryStore();

  List<StreamSource> streamSources = [];
  StreamSource? selectedSource;
  ChannelCatalog? catalog;
  bool _isLoading = true;
  String? _error;

  /// The selected tab: a [_Special] or a [Genre].
  Object _tab = _Special.home;

  /// The language the user wants: Hindi until they pick something else;
  /// null is "All languages". Remembered between launches.
  String? _preferredLanguage = 'Hindi';

  /// The language filter shown: the preferred one, or "All languages" when
  /// the playlist has no channels in it.
  String? _language;
  bool _hdOnly = false;

  /// The catalog the screen shows: everything, or only HD channels.
  ChannelCatalog get _view => _hdOnly ? catalog!.hdOnly : catalog!;

  @override
  void initState() {
    super.initState();
    library.load();
    _start();
  }

  @override
  void dispose() {
    library.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final sources = await channelsProvider.fetchStreamSources();
    if (!mounted) return;
    setState(() => streamSources = sources);
    if (sources.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'No playlists available';
      });
      return;
    }
    // Open the playlist and language used last time.
    String? last;
    try {
      final prefs = await SharedPreferences.getInstance();
      last = prefs.getString(_playlistKey);
      final language = prefs.getString(_languageKey);
      // Saved as '' for "All languages".
      if (language != null) {
        _preferredLanguage = language.isEmpty ? null : language;
      }
    } catch (_) {
      // Start with the first playlist, in Hindi.
    }
    await _loadSource(
        sources.firstWhere((s) => s.name == last, orElse: () => sources.first));
  }

  /// A list of the playlists to switch between, easy to use with a remote.
  Future<void> _choosePlaylist() async {
    final picked = await showDialog<StreamSource>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose a playlist'),
        children: [
          for (final source in streamSources)
            ListTile(
              autofocus: source == selectedSource,
              leading: Icon(source == selectedSource
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded),
              title: Text(source.name),
              onTap: () => Navigator.pop(context, source),
            ),
        ],
      ),
    );
    if (picked == null || picked == selectedSource) return;
    await _loadSource(picked);
    try {
      await (await SharedPreferences.getInstance())
          .setString(_playlistKey, picked.name);
    } catch (_) {
      // Not remembered; the playlist still loads.
    }
  }

  Future<void> _loadSource(StreamSource source) async {
    setState(() {
      _isLoading = true;
      _error = null;
      selectedSource = source;
    });
    try {
      final data = await channelsProvider.fetchCatalog(source);
      if (!mounted) return;
      setState(() {
        catalog = data;
        _isLoading = false;
        _tab = _Special.home;
        _language = data.languages.contains(_preferredLanguage)
            ? _preferredLanguage
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error =
            'There was a problem loading channels.\nCheck your internet connection.';
      });
    }
  }

  Future<void> _selectLanguage(String? language) async {
    setState(() => _language = _preferredLanguage = language);
    try {
      await (await SharedPreferences.getInstance())
          .setString(_languageKey, language ?? '');
    } catch (_) {
      // Not remembered; the filter still applies.
    }
  }

  /// Opens [channel]; [list] is the row or grid it was picked from, which
  /// the player flips through with channel up/down.
  Future<void> _openChannel(Channel channel, List<Channel> list) async {
    library.markWatched(channel.key);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            Player(channel: channel, library: library, channels: list),
      ),
    );
    // Redraw so channels that just failed show as "Not working".
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavourite(Channel channel) async {
    final added = await library.toggleFavourite(channel.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(added
            ? '${channel.name} added to favourites'
            : '${channel.name} removed from favourites'),
        duration: const Duration(seconds: 2),
      ));
  }

  List<Channel> _channelsFor(List<String> keys) {
    final all = _view.byKey;
    return [
      for (final key in keys)
        if (all[key] != null &&
            (_language == null || all[key]!.languages.contains(_language)))
          all[key]!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Icon(Icons.live_tv_rounded,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Live TV',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  if (selectedSource != null)
                    Text(
                      selectedSource!.name,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (catalog != null)
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchScreen(
                    catalog: catalog!,
                    library: library,
                    onOpen: _openChannel,
                    onToggleFavourite: _toggleFavourite,
                  ),
                ),
              ),
            ),
          if (streamSources.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.playlist_play_rounded),
                label: const Text('Playlists'),
                onPressed: _choosePlaylist,
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || catalog == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48),
              const SizedBox(height: 12),
              Text(_error ?? 'No channels', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                autofocus: true,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                onPressed: selectedSource == null
                    ? _start
                    : () => _loadSource(selectedSource!),
              ),
            ],
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final genres = _view.genresWithChannels(language: _language);
        final favourites = _channelsFor(library.favourites);
        final tabs = <Object>[
          _Special.home,
          if (favourites.isNotEmpty) _Special.favourites,
          ...genres,
        ];
        final tab = tabs.contains(_tab) ? _tab : _Special.home;
        final items = [for (final t in tabs) _barItem(t, favourites.length)];
        void select(int index) => setState(() => _tab = tabs[index]);

        final languageBar = LanguageBar(
          languages: catalog!.languages,
          selected: _language,
          onSelected: _selectLanguage,
          hdOnly: _hdOnly,
          onHdOnlyChanged: (value) => setState(() => _hdOnly = value),
        );
        final content = RefreshIndicator(
          onRefresh: () => _loadSource(selectedSource!),
          child: switch (tab) {
            _Special.home => _buildHomeRails(genres, favourites),
            _Special.favourites =>
              _buildGrid('Favourites', favourites, Icons.star_rounded),
            Genre genre => _buildGrid(genre.label,
                _view.filter(genre: genre, language: _language), genre.icon),
            _ => const SizedBox.shrink(),
          },
        );

        // TV and other wide screens: genre menu on the left, like the
        // Tata Play TV app. Phones: genre tabs across the top.
        if (_wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GenreSideNav(
                items: items,
                selected: tabs.indexOf(tab),
                onSelected: select,
                // The first "Continue watching" tile takes focus instead.
                autofocus: tab != _Special.home ||
                    _channelsFor(library.recent).isEmpty,
              ),
              Expanded(
                // Rows that scroll left stop at the menu's edge instead of
                // drawing over it.
                child: ClipRect(
                  child: Column(
                    children: [
                      languageBar,
                      const SizedBox(height: 4),
                      Expanded(child: content),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            GenreBar(
              items: items,
              selected: tabs.indexOf(tab),
              onSelected: select,
            ),
            languageBar,
            const SizedBox(height: 4),
            Expanded(child: content),
          ],
        );
      },
    );
  }

  /// Whether to use the TV layout.
  bool get _wide => Device.isTv || MediaQuery.sizeOf(context).width >= 720;

  GenreBarItem _barItem(Object tab, int favouriteCount) {
    final primary = Theme.of(context).colorScheme.primary;
    return switch (tab) {
      _Special.home =>
        GenreBarItem(label: 'Home', icon: Icons.home_rounded, color: primary),
      _Special.favourites => GenreBarItem(
          label: 'Favourites',
          icon: Icons.star_rounded,
          color: const Color(0xFFFFC94D),
          count: favouriteCount),
      Genre genre => GenreBarItem(
          label: genre.label,
          icon: genre.icon,
          color: genre.color,
          count: _view.filter(genre: genre, language: _language).length),
      _ => GenreBarItem(label: '', icon: Icons.circle, color: primary),
    };
  }

  Widget _buildHomeRails(List<Genre> genres, List<Channel> favourites) {
    final recent = _channelsFor(library.recent);
    final popular = _view.popular(language: _language);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (popular.isNotEmpty)
          _Rail(
            title: 'Top channels',
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFFF7043),
            channels: popular,
            tileBuilder: _tile,
            wide: _wide,
          ),
        if (recent.isNotEmpty)
          _Rail(
            title: 'Continue watching',
            icon: Icons.history_rounded,
            color: Theme.of(context).colorScheme.primary,
            channels: recent,
            // On TV the remote starts here: one OK resumes the last channel.
            tileBuilder: (channel, list) => _tile(channel, list,
                autofocus: Device.isTv && channel == recent.first),
            wide: _wide,
          ),
        if (favourites.isNotEmpty)
          _Rail(
            title: 'Favourites',
            icon: Icons.star_rounded,
            color: const Color(0xFFFFC94D),
            channels: favourites,
            tileBuilder: _tile,
            wide: _wide,
            onSeeAll: () => setState(() => _tab = _Special.favourites),
          ),
        for (final genre in genres)
          _Rail(
            title: genre.label,
            icon: genre.icon,
            color: genre.color,
            channels: _view.filter(genre: genre, language: _language),
            tileBuilder: _tile,
            wide: _wide,
            onSeeAll: () => setState(() => _tab = genre),
          ),
        if (recent.isEmpty && favourites.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              Device.isTv
                  ? 'Tip: hold OK on a channel to add it to Favourites.'
                  : 'Tip: long-press a channel to add it to Favourites.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(String title, List<Channel> channels, IconData icon) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Text(
                  '${channels.length} channels',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _wide ? 170 : 150,
              childAspectRatio: 0.9,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: channels.length,
            itemBuilder: (context, index) => _tile(channels[index], channels),
          ),
        ),
      ],
    );
  }

  Widget _tile(Channel channel, List<Channel> list, {bool autofocus = false}) =>
      ChannelTile(
        channel: channel,
        autofocus: autofocus,
        isFavourite: library.isFavourite(channel.key),
        onTap: () => _openChannel(channel, list),
        onLongPress: () => _toggleFavourite(channel),
      );
}

/// A titled, horizontally scrolling row of channels on the Home tab.
class _Rail extends StatelessWidget {
  static const maxTiles = 20;

  final String title;
  final IconData icon;
  final Color color;
  final List<Channel> channels;
  final Widget Function(Channel channel, List<Channel> list) tileBuilder;
  final bool wide;
  final VoidCallback? onSeeAll;

  const _Rail({
    required this.title,
    required this.icon,
    required this.color,
    required this.channels,
    required this.tileBuilder,
    required this.wide,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = channels.take(maxTiles).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 2),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('${channels.length}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('See all'),
                        Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: wide ? 172 : 146,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) => SizedBox(
                  width: wide ? 150 : 124,
                  child: tileBuilder(shown[index], channels)),
            ),
          ),
        ],
      ),
    );
  }
}
