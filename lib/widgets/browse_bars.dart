import 'package:flutter/material.dart';

/// One entry of the genre bar.
class GenreBarItem {
  final String label;
  final IconData icon;
  final Color color;
  final int? count;

  const GenreBarItem({
    required this.label,
    required this.icon,
    required this.color,
    this.count,
  });
}

/// The row of genre tabs under the app bar on phones
/// (Home, Entertainment, Movies...).
class GenreBar extends StatelessWidget {
  final List<GenreBarItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  const GenreBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) => _GenreTab(
          item: items[index],
          selected: index == selected,
          vertical: false,
          onTap: () => onSelected(index),
        ),
      ),
    );
  }
}

/// The genre menu down the left side of the screen on TVs.
///
/// When focus comes into the menu from the channels, it lands on the
/// selected genre rather than on whichever genre happens to be closest.
class GenreSideNav extends StatefulWidget {
  final List<GenreBarItem> items;
  final int selected;
  final ValueChanged<int> onSelected;

  const GenreSideNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<GenreSideNav> createState() => _GenreSideNavState();
}

class _GenreSideNavState extends State<GenreSideNav> {
  final List<FocusNode> _nodes = [];

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _node(int index) {
    while (_nodes.length <= index) {
      _nodes.add(FocusNode(debugLabel: 'genre ${_nodes.length}'));
    }
    return _nodes[index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && widget.selected < widget.items.length) {
          final selectedNode = _node(widget.selected);
          if (!selectedNode.hasFocus) selectedNode.requestFocus();
        }
      },
      child: Container(
        width: 210,
        color: theme.colorScheme.surfaceContainer,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: widget.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) => _GenreTab(
            item: widget.items[index],
            selected: index == widget.selected,
            vertical: true,
            focusNode: _node(index),
            autofocus: index == widget.selected,
            onTap: () => widget.onSelected(index),
          ),
        ),
      ),
    );
  }
}

class _GenreTab extends StatefulWidget {
  final GenreBarItem item;
  final bool selected;
  final bool vertical;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback onTap;

  const _GenreTab({
    required this.item,
    required this.selected,
    required this.vertical,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<_GenreTab> createState() => _GenreTabState();
}

class _GenreTabState extends State<_GenreTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final selected = widget.selected;
    final iconColor =
        selected ? item.color : theme.colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: widget.vertical ? 14 : null,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected || _focused
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
    );

    final content = widget.vertical
        ? Row(
            children: [
              Icon(item.icon, color: iconColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle),
              ),
              if (item.count != null)
                Text('${item.count}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, color: iconColor, size: 24),
              const SizedBox(height: 4),
              Text(item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle),
            ],
          );

    return InkWell(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(14),
      onTap: widget.onTap,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: widget.vertical ? null : 86,
        padding: widget.vertical
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
            : null,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? item.color.withValues(alpha: 0.22)
              : _focused
                  ? theme.colorScheme.surfaceContainerHighest
                  : widget.vertical
                      ? Colors.transparent
                      : theme.colorScheme.surfaceContainer,
          border: Border.all(
            color: _focused
                ? theme.colorScheme.onSurface
                : selected
                    ? item.color
                    : Colors.transparent,
            width: _focused ? 2.5 : 1.5,
          ),
        ),
        child: content,
      ),
    );
  }
}

/// The row of language filters ("All languages", Hindi, Tamil...).
class LanguageBar extends StatelessWidget {
  final List<String> languages;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const LanguageBar({
    super.key,
    required this.languages,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final options = <String?>[null, ...languages];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final language = options[index];
          return _LanguagePill(
            label: language ?? 'All languages',
            selected: language == selected,
            onTap: () => onSelected(language),
          );
        },
      ),
    );
  }
}

class _LanguagePill extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguagePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_LanguagePill> createState() => _LanguagePillState();
}

class _LanguagePillState extends State<_LanguagePill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: widget.onTap,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: widget.selected ? scheme.primary : Colors.transparent,
          border: Border.all(
            color: _focused
                ? scheme.onSurface
                : widget.selected
                    ? scheme.primary
                    : scheme.outlineVariant,
            width: _focused ? 2.5 : 1,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
            color: widget.selected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
