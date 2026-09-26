import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

class RoomReaderEntry {
  const RoomReaderEntry({
    required this.profile,
    required this.readAt,
  });

  final Profile profile;
  final DateTime readAt;
}

/// Bottom sheet listing everyone who has read the message.
Future<void> showRoomReadersSheet(
  BuildContext context, {
  required List<RoomReaderEntry> readers,
}) async {
  if (readers.isEmpty) {
    return;
  }

  await showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final l10n = L10n.of(sheetContext)!;
      final tt = sheetContext.tt;
      final now = DateTime.now();

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: tt.screenHPadding,
                  right: tt.screenHPadding,
                  top: tt.rowGap,
                  bottom: tt.rowGap,
                ),
                child: Text(
                  l10n.beaconRoomReadByTitle,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const Divider(height: 1),
              for (var i = 0; i < readers.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ReaderRow(
                  entry: readers[i],
                  l10n: l10n,
                  now: now,
                  tt: tt,
                  theme: theme,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _ReaderRow extends StatelessWidget {
  const _ReaderRow({
    required this.entry,
    required this.l10n,
    required this.now,
    required this.tt,
    required this.theme,
  });

  final RoomReaderEntry entry;
  final L10n l10n;
  final DateTime now;
  final TenturaTokens tt;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final whenLabel = compactRelativeTimeAgo(
      when: entry.readAt,
      now: now,
      l10n: l10n,
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.rowGap,
      ),
      child: Row(
        children: [
          TenturaAvatar.medium(
            profile: entry.profile,
            size: tt.avatarSize,
          ),
          SizedBox(width: tt.avatarTextGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.profile.shownName,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.beaconRoomReadAtRelative(whenLabel),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tt.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
