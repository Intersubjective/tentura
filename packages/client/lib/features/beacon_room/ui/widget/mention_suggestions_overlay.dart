import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/presence_avatar.dart';

const double _kMentionOverlayMargin = 8;
const double _kMentionOverlayMaxWidth = 360;
const double _kMentionOverlayMinWidth = 0;
const double _kMentionSuggestionRowHeight = 56;

final class MentionSuggestionsOverlay extends StatefulWidget {
  const MentionSuggestionsOverlay({
    required this.suggestions,
    required this.anchor,
    required this.onSelect,
    required this.onDismiss,
    super.key,
  });

  final List<BeaconParticipant> suggestions;
  final Rect anchor;
  final void Function(BeaconParticipant participant) onSelect;
  final VoidCallback onDismiss;

  @override
  State<MentionSuggestionsOverlay> createState() =>
      _MentionSuggestionsOverlayState();
}

class _MentionSuggestionsOverlayState extends State<MentionSuggestionsOverlay> {
  int _selectedIndex = 0;

  void _selectAt(int index) {
    if (widget.suggestions.isEmpty) return;
    final i = index.clamp(0, widget.suggestions.length - 1);
    setState(() => _selectedIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = widget.suggestions;
    if (list.isEmpty) return const SizedBox.shrink();

    final max = list.length < 5 ? list.length : 5;
    final height = max * _kMentionSuggestionRowHeight;

    return Positioned.fill(
      child: TextFieldTapRegion(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final left = widget.anchor.left
                .clamp(
                  _kMentionOverlayMargin,
                  math.max(
                    _kMentionOverlayMargin,
                    constraints.maxWidth - _kMentionOverlayMargin,
                  ),
                )
                .toDouble();
            final width = math.min(
              _kMentionOverlayMaxWidth,
              math.max(
                _kMentionOverlayMinWidth,
                constraints.maxWidth - left - _kMentionOverlayMargin,
              ),
            );
            final top = math.max(
              _kMentionOverlayMargin,
              widget.anchor.top - height - _kMentionOverlayMargin,
            );

            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                final position = event.localPosition;
                final insideCard =
                    position.dx >= left &&
                    position.dx <= left + width &&
                    position.dy >= top &&
                    position.dy <= top + height;
                if (!insideCard) {
                  widget.onDismiss();
                  return;
                }

                final index =
                    ((position.dy - top) / _kMentionSuggestionRowHeight)
                        .floor()
                        .clamp(0, max - 1);
                widget.onSelect(list[index]);
              },
              child: Stack(
                children: [
                  Positioned(
                    left: left,
                    top: top,
                    width: width,
                    height: height,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < max; i++)
                            SizedBox(
                              height: _kMentionSuggestionRowHeight,
                              child: _row(
                                theme,
                                list[i],
                                selected: i == _selectedIndex,
                                index: i,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
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
    return MouseRegion(
      onEnter: (_) => _selectAt(index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelect(p),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.surfaceContainerHighest : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                PresenceAvatar.small(
                  profile: p.toProfile(),
                  userId: p.userId,
                  size: 28,
                ),
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
      ),
    );
  }
}

extension on BeaconParticipant {
  Profile toProfile() => Profile(
    id: userId,
    displayName: userTitle,
  );
}
