import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../bloc/beacon_lobby_cubit.dart';
import 'beacon_lobby_subtitle.dart';

/// The Request Questions screen's content under its top bar (internally the
/// lobby, U088).
class BeaconLobbyBody extends StatefulWidget {
  const BeaconLobbyBody({required this.myUserId, super.key});

  final String myUserId;

  @override
  State<BeaconLobbyBody> createState() => _BeaconLobbyBodyState();
}

class _BeaconLobbyBodyState extends State<BeaconLobbyBody> {
  final _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _confirmBan(
    BeaconLobbyCubit cubit,
    String userId,
    String name,
  ) async {
    final l10n = L10n.of(context)!;
    final ok = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.beaconLobbyBanConfirmTitle(
        name.isEmpty ? l10n.beaconLobbySomeone : name,
      ),
      // True whether or not they offered help (#657).
      content: l10n.beaconLobbyRemoveConfirmBody,
      confirmLabel: l10n.beaconLobbyBanAction,
    );
    if (ok ?? false) await cubit.ban(userId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<BeaconLobbyCubit>();
    return BlocConsumer<BeaconLobbyCubit, BeaconLobbyState>(
      listenWhen: (p, c) => c.postedCount > p.postedCount,
      listener: (_, _) => _composer.clear(),
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                onUnban: (id) => unawaited(cubit.unban(id)),
              ),
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: cubit.refresh,
                child: state.messages.isEmpty
                    ? CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: TenturaEmptyState(
                              key: const Key('beaconLobbyEmpty'),
                              icon: TenturaIcons.comments,
                              title: l10n.beaconLobbyEmpty,
                              body: state.isAuthor
                                  ? l10n.beaconLobbyEmptyBodyAuthor
                                  : l10n.beaconLobbyEmptyBody,
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        children: [
                          if (state.hasOlder)
                            Center(
                              child: TextButton(
                                key: const Key('beaconLobbyLoadOlder'),
                                onPressed: state.loadingOlder
                                    ? null
                                    : () => unawaited(cubit.loadOlder()),
                                child: Text(l10n.beaconLobbyLoadOlder),
                              ),
                            ),
                          for (final m in state.messages)
                            _LobbyMessageTile(
                              message: m,
                              byAuthor:
                                  state.authorId.isNotEmpty &&
                                  m.authorId == state.authorId,
                              // Nobody asks on a closed Request, so
                              // there is no one to remove (#657).
                              canBan:
                                  state.isAuthor &&
                                  state.readOnlyReason !=
                                      BeaconLobbyLimitReason.closed &&
                                  m.authorId != widget.myUserId &&
                                  !state.isBanned(m.authorId),
                              onBan: () => unawaited(
                                _confirmBan(cubit, m.authorId, m.authorName),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            if (state.canPost)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tt.screenHPadding,
                  vertical: tt.rowGap,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('beaconLobbyComposer'),
                        controller: _composer,
                        minLines: 1,
                        maxLines: 4,
                        // Like the Chat composer (#658): Enter sends.
                        textInputAction: TextInputAction.send,
                        // Keep the focus for the next message (the default
                        // would drop it after a send action).
                        onEditingComplete: () {},
                        onSubmitted: (text) {
                          if (!state.sending) unawaited(cubit.post(text));
                        },
                        decoration: InputDecoration(
                          hintText: state.isAuthor
                              ? l10n.beaconLobbyComposerHintAuthor
                              : l10n.beaconLobbyComposerHint,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('beaconLobbySend'),
                      tooltip: l10n.beaconLobbySend,
                      icon: const Icon(TenturaIcons.send),
                      onPressed: state.sending
                          ? null
                          : () => unawaited(cubit.post(_composer.text)),
                    ),
                  ],
                ),
              )
            else if (state.info != null)
              Padding(
                key: const Key('beaconLobbyReadOnly'),
                padding: tt.listRowPadding,
                child: Text(
                  // Nobody can offer again once the Request stops taking
                  // offers: closed wins over the reader's own act (#657).
                  beaconLobbyReadOnlyText(
                    l10n,
                    state.closedToOffers
                        ? BeaconLobbyLimitReason.closed
                        : state.readOnlyReason,
                  ),
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The read-only note under the thread, naming the viewer's own reason
/// when the server gives one (#657).
String beaconLobbyReadOnlyText(L10n l10n, BeaconLobbyLimitReason? reason) =>
    switch (reason) {
      BeaconLobbyLimitReason.closed => l10n.beaconLobbyReadOnlyClosed,
      BeaconLobbyLimitReason.cantHelp => l10n.beaconLobbyReadOnlyCantHelp,
      BeaconLobbyLimitReason.withdrew => l10n.beaconLobbyReadOnlyWithdrew,
      BeaconLobbyLimitReason.declined => l10n.beaconLobbyReadOnlyDeclined,
      BeaconLobbyLimitReason.removed || null => l10n.beaconLobbyReadOnly,
    };

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

/// One Questions message: a deliberately light version of the room message
/// tile (author, time, text, and the author's remove action).
class _LobbyMessageTile extends StatelessWidget {
  const _LobbyMessageTile({
    required this.message,
    required this.byAuthor,
    required this.canBan,
    required this.onBan,
  });

  final BeaconLobbyMessage message;

  /// Written by the Request author: marked, so readers tell answers from
  /// questions (#657).
  final bool byAuthor;
  final bool canBan;
  final VoidCallback onBan;

  @override
  Widget build(BuildContext context) {
    final at = message.createdAt;
    final loc = MaterialLocalizations.of(context);
    final tt = context.tt;
    return ListTile(
      title: Row(
        children: [
          Flexible(child: Text(message.authorName)),
          if (byAuthor) ...[
            SizedBox(width: tt.iconTextGap),
            TenturaTypeLabel(
              L10n.of(context)!.beaconLobbyAuthorBadge,
              key: const Key('beaconLobbyAuthorBadge'),
            ),
          ],
          if (at != null) ...[
            SizedBox(width: tt.iconTextGap),
            TenturaMetaText(
              '${loc.formatShortDate(at)} '
              '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
            ),
          ],
        ],
      ),
      subtitle: Text(message.body),
      trailing: canBan
          ? IconButton(
              tooltip: L10n.of(context)!.beaconLobbyBanAction,
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: onBan,
            )
          : null,
    );
  }
}
