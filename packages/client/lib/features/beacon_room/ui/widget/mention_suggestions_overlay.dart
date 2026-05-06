import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/self_aware_plain_mini_avatar.dart';

final class MentionSuggestionsOverlay extends StatefulWidget {
  const MentionSuggestionsOverlay({
    required this.suggestions,
    required this.layerLink,
    required this.onSelect,
    required this.onDismiss,
    super.key,
  });

  final List<BeaconParticipant> suggestions;
  final LayerLink layerLink;
  final void Function(BeaconParticipant participant) onSelect;
  final VoidCallback onDismiss;

  @override
  State<MentionSuggestionsOverlay> createState() =>
      _MentionSuggestionsOverlayState();
}

class _MentionSuggestionsOverlayState extends State<MentionSuggestionsOverlay> {
  final _focusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAt(int index) {
    if (widget.suggestions.isEmpty) return;
    final i = index.clamp(0, widget.suggestions.length - 1);
    setState(() => _selectedIndex = i);
  }

  void _confirm() {
    if (widget.suggestions.isEmpty) return;
    widget.onSelect(widget.suggestions[_selectedIndex]);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _selectAt(_selectedIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _selectAt(_selectedIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      _confirm();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = widget.suggestions;
    if (list.isEmpty) return const SizedBox.shrink();

    final max = list.length < 5 ? list.length : 5;

    return CompositedTransformFollower(
      link: widget.layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      offset: const Offset(0, -8),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < max; i++)
                  _row(theme, list[i], selected: i == _selectedIndex, index: i),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    BeaconParticipant p, {
    required bool selected,
    required int index,
  }) {
    final title = p.userTitle.trim();
    return InkWell(
      onTap: () => widget.onSelect(p),
      onHover: (h) {
        if (h) _selectAt(index);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.surfaceContainerHighest : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SelfAwarePlainMiniAvatar(profile: p.toProfile(), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${p.handle}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on BeaconParticipant {
  Profile toProfile() => Profile(
        id: userId,
        title: userTitle,
      );
}


