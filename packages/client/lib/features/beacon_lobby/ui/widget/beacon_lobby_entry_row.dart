import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/use_case/beacon_lobby_case.dart';
import '../bloc/beacon_lobby_entry_cubit.dart';
import 'beacon_lobby_subtitle.dart';

/// The way into a Request's Questions. Shown only when the server policy
/// says the viewer may read Questions (the client never re-implements who is
/// in the audience).
///
/// [prominent] is the card on the Request page of someone who is not inside
/// yet (#526: asking before offering is the point); otherwise it is a list
/// row on the inside Overview.
class BeaconLobbyEntryRow extends StatelessWidget {
  const BeaconLobbyEntryRow({
    required this.beaconId,
    this.isAuthor = false,
    this.standing,
    this.prominent = false,
    super.key,
  });

  /// Finder key of the entry, in both variants.
  static const entryKey = Key('beaconLobbyEntry');

  final String beaconId;

  /// The viewer wrote the Request: the copy speaks to the one who answers.
  final bool isAuthor;

  /// The viewer's standing as the Request page knows it (author, offer,
  /// admission, "Can't help", status…). Whenever it changes the access is
  /// read again: realtime does not tell the viewer about every one of their
  /// own changes (#655).
  final Object? standing;

  final bool prominent;

  @override
  Widget build(BuildContext context) =>
      // Not wired (isolated widget tests of the Request page): no row.
      !GetIt.I.isRegistered<BeaconLobbyCase>()
      ? const SizedBox.shrink()
      : BlocProvider(
          key: ValueKey(beaconId),
          create: (_) {
            final cubit = BeaconLobbyEntryCubit(
              GetIt.I<BeaconLobbyCase>(),
              beaconId: beaconId,
            );
            unawaited(cubit.load());
            return cubit;
          },
          child: _StandingWatcher(
            standing: standing,
            child: BlocBuilder<BeaconLobbyEntryCubit, BeaconLobbyAccess?>(
              builder: (context, access) {
                if (access == null || !access.canRead) {
                  return const SizedBox.shrink();
                }
                Future<void> open() async {
                  await context.router.push(
                    BeaconLobbyRoute(beaconId: beaconId),
                  );
                  if (context.mounted) {
                    await context.read<BeaconLobbyEntryCubit>().load();
                  }
                }

                return prominent
                    ? _EntryCard(
                        access: access,
                        isAuthor: isAuthor,
                        onTap: open,
                      )
                    : _EntryTile(
                        access: access,
                        isAuthor: isAuthor,
                        onTap: open,
                      );
              },
            ),
          ),
        );
}

/// Reads the access again when [standing] changes.
class _StandingWatcher extends StatefulWidget {
  const _StandingWatcher({required this.standing, required this.child});

  final Object? standing;
  final Widget child;

  @override
  State<_StandingWatcher> createState() => _StandingWatcherState();
}

class _StandingWatcherState extends State<_StandingWatcher> {
  @override
  void didUpdateWidget(covariant _StandingWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.standing != widget.standing) {
      unawaited(context.read<BeaconLobbyEntryCubit>().load());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _subtitle(
  L10n l10n,
  BeaconLobbyAccess access, {
  required bool isAuthor,
}) => beaconLobbySubtitle(
  l10n,
  isAuthor: isAuthor,
  isHelper: access.isHelper,
  closed: beaconLobbyClosedToOffers(
    takesOffers: access.takesOffers,
    reason: access.limitReason,
  ),
);

/// The viewer's unread Questions, falling back to the visible total.
class _CountLine extends StatelessWidget {
  const _CountLine({required this.access});

  final BeaconLobbyAccess access;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return TenturaMetaText(
      access.unreadCount == 0
          ? l10n.beaconLobbyEntryCount(access.messageCount)
          : l10n.beaconLobbyEntryUnread(access.unreadCount),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.access,
    required this.isAuthor,
    required this.onTap,
  });

  final BeaconLobbyAccess access;
  final bool isAuthor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return ListTile(
      key: BeaconLobbyEntryRow.entryKey,
      leading: const Icon(TenturaIcons.comments),
      title: Text(l10n.beaconLobbyTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_subtitle(l10n, access, isAuthor: isAuthor)),
          _CountLine(access: access),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// The recipient's card: what Questions is for, in one line, and how many
/// messages are already there.
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.access,
    required this.isAuthor,
    required this.onTap,
  });

  final BeaconLobbyAccess access;
  final bool isAuthor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: tt.rowGap),
      child: Semantics(
        button: true,
        child: TenturaTechCard(
          key: BeaconLobbyEntryRow.entryKey,
          onTap: onTap,
          child: Row(
            children: [
              Icon(
                TenturaIcons.comments,
                size: tt.iconSize,
                color: scheme.primary,
              ),
              SizedBox(width: tt.avatarTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.beaconLobbyTitle,
                      style: TenturaText.titleSmall(tt.text),
                    ),
                    SizedBox(height: tt.tightGap),
                    Text(
                      _subtitle(l10n, access, isAuthor: isAuthor),
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                    _CountLine(access: access),
                  ],
                ),
              ),
              SizedBox(width: tt.iconTextGap),
              Icon(Icons.chevron_right, color: tt.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
