import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/browser_context_menu_hold.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../bloc/beacon_lobby_cubit.dart';
import 'beacon_lobby_subtitle.dart';

/// The Request Questions screen's content under its top bar (internally the
/// lobby, U088): the shared Request chat on the Questions thread (#726),
/// with the features limited to admitted people off. [BeaconLobbyCubit]
/// above says who may read or post.
class BeaconLobbyChat extends StatelessWidget {
  const BeaconLobbyChat({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<BeaconLobbyCubit>();
    return BlocBuilder<BeaconLobbyCubit, BeaconLobbyState>(
      builder: (context, state) {
        final info = state.info;
        final loadError = state.loadError;
        if (loadError != null) {
          return ScreenLoadErrorPanel(
            details: describeScreenLoadError(error: loadError, l10n: l10n),
            onRetry: () => unawaited(cubit.load()),
          );
        }
        if (state.unavailable) {
          return TenturaEmptyState(
            key: const Key('beaconLobbyUnavailable'),
            icon: TenturaIcons.comments,
            title: l10n.beaconLobbyTitle,
            body: state.unavailableReason == BeaconLobbyLimitReason.removed
                ? l10n.beaconLobbyUnavailableRemoved
                : l10n.beaconLobbyUnavailable,
          );
        }
        if (info == null) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        // A new standing (may post or not) starts the chat over.
        return BlocProvider<RoomCubit>(
          key: ValueKey((info.lobbyId, info.canPost)),
          create: (_) => RoomCubit(
            beaconId: info.beaconId,
            threadItemId: info.lobbyId,
            lobbyAccess: BeaconLobbyAccess(
              canRead: true,
              canPost: info.canPost,
            ),
            capabilities: const RoomCapabilities.questions(),
          ),
          // Right-click on a message opens its actions (#456, #623).
          child: BrowserContextMenuHold(
            child: TenturaChatColumn(
              child: BeaconRoomBody(
                capabilities: const RoomCapabilities.questions(),
                beaconAuthorId: info.authorId,
                header: _QuestionsHeader(state: state),
                // Nobody can offer again once the Request stops taking
                // offers: closed wins over the reader's own act (#657).
                readOnlyHint: beaconLobbyReadOnlyText(
                  l10n,
                  state.closedToOffers
                      ? BeaconLobbyLimitReason.closed
                      : state.readOnlyReason,
                ),
                // Nobody asks on a closed Request, so there is no one to
                // remove (#657).
                onRemoveAuthor:
                    state.isAuthor &&
                        state.readOnlyReason != BeaconLobbyLimitReason.closed
                    ? (message) => unawaited(_confirmBan(context, message))
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmBan(BuildContext context, RoomMessage message) async {
    final cubit = context.read<BeaconLobbyCubit>();
    if (cubit.state.isBanned(message.authorId)) return;
    final l10n = L10n.of(context)!;
    final name = message.author.shownName;
    final ok = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.beaconLobbyBanConfirmTitle(
        name.isEmpty ? l10n.beaconLobbySomeone : name,
      ),
      // True whether or not they offered help (#657).
      content: l10n.beaconLobbyRemoveConfirmBody,
      confirmLabel: l10n.beaconLobbyBanAction,
    );
    if (ok ?? false) await cubit.ban(message.authorId);
  }
}

/// The read-only hint of the Questions composer, naming the viewer's own
/// reason when the server gives one (#657).
String beaconLobbyReadOnlyText(L10n l10n, BeaconLobbyLimitReason? reason) =>
    switch (reason) {
      BeaconLobbyLimitReason.closed => l10n.beaconLobbyReadOnlyClosed,
      BeaconLobbyLimitReason.cantHelp => l10n.beaconLobbyReadOnlyCantHelp,
      BeaconLobbyLimitReason.withdrew => l10n.beaconLobbyReadOnlyWithdrew,
      BeaconLobbyLimitReason.declined => l10n.beaconLobbyReadOnlyDeclined,
      BeaconLobbyLimitReason.removed || null => l10n.beaconLobbyReadOnly,
    };

/// Above the Questions messages: what Questions is for the one reading, and
/// the author's fold of people removed from it.
class _QuestionsHeader extends StatelessWidget {
  const _QuestionsHeader({required this.state});

  final BeaconLobbyState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: tt.listRowPadding,
          child: Text(
            // Copy for the one reading and the Request's state (#657).
            beaconLobbySubtitle(
              l10n,
              isAuthor: state.isAuthor,
              isHelper: state.isHelper,
              closed: state.closedToOffers,
            ),
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
        if (state.isAuthor && state.banned.isNotEmpty)
          _BannedFold(
            banned: state.banned,
            onUnban: (id) =>
                unawaited(context.read<BeaconLobbyCubit>().unban(id)),
          ),
      ],
    );
  }
}

/// The author's fold of people removed from Questions, with names from the
/// server (never from route arguments).
class _BannedFold extends StatelessWidget {
  const _BannedFold({required this.banned, required this.onUnban});

  final List<BeaconLobbyBannedPerson> banned;
  final ValueChanged<String> onUnban;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return ExpansionTile(
      key: const Key('beaconLobbyBannedFold'),
      title: Semantics(
        label: l10n.beaconLobbyBannedCountSemantics(banned.length),
        excludeSemantics: true,
        child: Row(
          children: [
            Flexible(child: Text(l10n.beaconLobbyBannedHeading)),
            SizedBox(width: tt.iconTextGap),
            TenturaMetaText('${banned.length}'),
          ],
        ),
      ),
      children: [
        for (final b in banned)
          ListTile(
            title: Text(b.name.isEmpty ? l10n.beaconLobbySomeone : b.name),
            trailing: TextButton(
              onPressed: () => onUnban(b.userId),
              child: Text(l10n.beaconLobbyUnbanAction),
            ),
          ),
      ],
    );
  }
}
