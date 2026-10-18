import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/channel.dart';

/// Remote and keyboard keys that open a channel.
final _selectKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// A channel card: logo on top, name and language underneath. Works with
/// touch and with a TV remote: it grows and gets an outline when focused,
/// OK opens the channel and holding OK works like a long-press.
class ChannelTile extends StatefulWidget {
  final Channel channel;
  final bool isFavourite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool autofocus;

  const ChannelTile({
    super.key,
    required this.channel,
    required this.isFavourite,
    required this.onTap,
    required this.onLongPress,
    this.autofocus = false,
  });

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  bool _focused = false;
  bool _selectDown = false;
  bool _heldDown = false;

  /// OK on a remote: open on release, or long-press if held. The key
  /// repeats while held, which is how Android TV reports a long press.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_selectKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _selectDown = true;
      _heldDown = false;
    } else if (event is KeyRepeatEvent) {
      if (_selectDown && !_heldDown) {
        _heldDown = true;
        widget.onLongPress();
      }
    } else if (event is KeyUpEvent) {
      if (_selectDown && !_heldDown) widget.onTap();
      _selectDown = false;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channel = widget.channel;
    final subtitle = [
      if (channel.languages.isNotEmpty) channel.languages.first,
      if (channel.isHd) 'HD',
    ].join(' · ');

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: AnimatedScale(
        scale: _focused ? 1.06 : 1,
        duration: const Duration(milliseconds: 120),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(14),
          // The outline and zoom already show focus.
          focusColor: Colors.transparent,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 11,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _focused
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ChannelLogo(channel: channel),
                        ),
                        if (widget.isFavourite)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(Icons.star_rounded,
                                size: 18, color: Color(0xFFFFC94D)),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: Text(
                    channel.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      height: 1.2,
                    ),
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The channel logo, or the channel's initials on its genre colour when
/// there is no logo or it fails to load.
class ChannelLogo extends StatelessWidget {
  final Channel channel;

  const ChannelLogo({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final fallback = _Initials(channel: channel);
    final url = channel.logoUrl;
    if (url == null) return fallback;
    return Image.network(
      url,
      fit: BoxFit.contain,
      cacheWidth: 240,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          Padding(padding: const EdgeInsets.all(10), child: child),
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class _Initials extends StatelessWidget {
  final Channel channel;

  const _Initials({required this.channel});

  @override
  Widget build(BuildContext context) {
    final color = channel.primaryGenre.color;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.4)],
        ),
      ),
      child: Center(
        child: Text(
          channel.initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
