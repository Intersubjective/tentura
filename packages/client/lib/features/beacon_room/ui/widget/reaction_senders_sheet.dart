import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Telegram-style bottom sheet: tab by emoji, list of people who reacted.
Future<void> showReactionSendersSheet(
  BuildContext context, {
  required Map<String, List<Profile>> reactors,
  required Map<String, int> reactionCounts,
  required String initialEmoji,
}) async {
  final keys = reactionCounts.keys.toList()
    ..sort((a, b) {
      final c = -(reactionCounts[a] ?? 0).compareTo(reactionCounts[b] ?? 0);
      if (c != 0) {
        return c;
      }
      return a.compareTo(b);
    });
  if (keys.isEmpty) {
    return;
  }
  var selected = keys.contains(initialEmoji) ? initialEmoji : keys.first;

  await showTenturaAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      final l10n = L10n.of(sheetContext)!;
      final tt = sheetContext.tt;

      return SafeArea(
        child: Semantics(
          label: l10n.beaconRoomReactionSendersSheetSemantic,
          child: DraggableScrollableSheet(
            initialChildSize: 0.42,
            maxChildSize: 0.88,
            snap: true,
            snapSizes: const [0.42, 0.88],
            builder: (context, scrollController) {
              return StatefulBuilder(
                builder: (context, setModalState) {
                  final senders = reactors[selected] ?? const <Profile>[];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: tt.rowGap,
                            bottom: tt.tightGap * 2,
                          ),
                          child: Container(
                            width: tt.buttonHeight,
                            height: tt.tightGap * 2,
                            decoration: BoxDecoration(
                              color: scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(
                                tt.cardRadius,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: tt.screenHPadding,
                          right: tt.screenHPadding,
                          bottom: tt.rowGap,
                        ),
                        child: Text(
                          l10n.beaconRoomReactionSendersSheetTitle,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(
                        height: 48,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                            horizontal: tt.screenHPadding,
                          ),
                          itemCount: keys.length,
                          separatorBuilder: (context, index) =>
                              SizedBox(width: tt.rowGap),
                          itemBuilder: (context, i) {
                            final emoji = keys[i];
                            final active = emoji == selected;
                            return FilterChip(
                              selected: active,
                              showCheckmark: false,
                              label: Text(
                                emoji,
                                style: theme.textTheme.titleMedium,
                              ),
                              onSelected: (_) {
                                setModalState(() {
                                  selected = emoji;
                                });
                              },
                              selectedColor: scheme.primaryContainer,
                              side: BorderSide(
                                color: active
                                    ? scheme.primary
                                    : scheme.outlineVariant,
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          padding: EdgeInsets.only(
                            left: tt.screenHPadding,
                            right: tt.screenHPadding,
                            top: tt.rowGap,
                          ),
                          itemCount: senders.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = senders[i];
                            return SizedBox(
                              height: 48,
                              child: Row(
                                children: [
                                  TenturaAvatar.medium(
                                    profile: p,
                                    size: tt.avatarSize,
                                  ),
                                  SizedBox(width: tt.avatarTextGap),
                                  Expanded(
                                    child: Text(
                                      p.shownName,
                                      style: theme.textTheme.bodyMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      );
    },
  );
}
