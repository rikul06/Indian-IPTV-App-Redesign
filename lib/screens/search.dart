import 'package:flutter/material.dart';

import '../model/channel.dart';
import '../model/channel_catalog.dart';
import '../services/library_store.dart';
import '../widgets/channel_tile.dart';

/// Searches every channel of the playlist by name, language or genre.
class SearchScreen extends StatefulWidget {
  final ChannelCatalog catalog;
  final LibraryStore library;
  final ValueChanged<Channel> onOpen;
  final ValueChanged<Channel> onToggleFavourite;

  const SearchScreen({
    super.key,
    required this.catalog,
    required this.library,
    required this.onOpen,
    required this.onToggleFavourite,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController searchController = TextEditingController();
  List<Channel> results = [];

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (query) =>
              setState(() => results = widget.catalog.search(query)),
          decoration: InputDecoration(
            hintText: 'Search channels, languages, genres',
            border: InputBorder.none,
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      searchController.clear();
                      results = [];
                    }),
                  ),
          ),
        ),
      ),
      body: searchController.text.trim().isEmpty
          ? Center(
              child: Text('Type a channel name, e.g. "news" or "Tamil"',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            )
          : results.isEmpty
              ? const Center(child: Text('No channels found'))
              : ListenableBuilder(
                  listenable: widget.library,
                  builder: (context, _) => GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 150,
                      childAspectRatio: 0.9,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final channel = results[index];
                      return ChannelTile(
                        channel: channel,
                        isFavourite: widget.library.isFavourite(channel.key),
                        onTap: () => widget.onOpen(channel),
                        onLongPress: () => widget.onToggleFavourite(channel),
                      );
                    },
                  ),
                ),
    );
  }
}
