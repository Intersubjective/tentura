import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../bloc/beacon_lobby_cubit.dart';

/// The lobby screen's content under its top bar (U088).
class BeaconLobbyBody extends StatefulWidget {
  const BeaconLobbyBody({
    required this.myUserId,
    this.knownNames = const {},
    super.key,
  });

  final String myUserId;

  /// Display names by user id (help offerers), for the removed list.
  final Map<String, String> knownNames;

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

  /// A removed person with no live offer and no message here has no known
  /// name: show "someone", never an internal id.
  String _nameOf(String userId, BeaconLobbyState state, L10n l10n) {
    final known = widget.knownNames[userId];
    if (known != null && known.isNotEmpty) return known;
    for (final m in state.messages) {
      if (m.authorId == userId && m.authorName.isNotEmpty) return m.authorName;
    }
    return l10n.beaconLobbySomeone;
  }

  Future<void> _confirmBan(
    BeaconLobbyCubit cubit,
    String userId,
    String name,
  ) async {
    final l10n = L10n.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.beaconLobbyBanConfirmTitle(name)),
        content: Text(l10n.beaconLobbyBanConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.beaconLobbyBanAction),
          ),
        ],
      ),
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
          return Center(
            child: Padding(
              padding: tt.cardPadding,
              child: Text(
                l10n.beaconLobbyUnavailable,
                textAlign: TextAlign.center,
                style: TenturaText.body(tt.textMuted),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: tt.listRowPadding,
              child: Text(
                l10n.beaconLobbyEntrySubtitle,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ),
            if (state.isAuthor && state.bannedUserIds.isNotEmpty)
              ExpansionTile(
                key: const Key('beaconLobbyBannedFold'),
                title: Row(
                  children: [
                    Flexible(child: Text(l10n.beaconLobbyBannedHeading)),
                    SizedBox(width: tt.iconTextGap),
                    Text(
                      '${state.bannedUserIds.length}',
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                  ],
                ),
                children: [
                  for (final id in state.bannedUserIds)
                    ListTile(
                      title: Text(_nameOf(id, state, l10n)),
                      trailing: TextButton(
                        onPressed: () => unawaited(cubit.unban(id)),
                        child: Text(l10n.beaconLobbyUnbanAction),
                      ),
                    ),
                ],
              ),
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: cubit.refresh,
                child: state.messages.isEmpty
                    ? ListView(
                        children: [
                          Padding(
                            padding: tt.cardPadding,
                            child: Text(
                              l10n.beaconLobbyEmpty,
                              textAlign: TextAlign.center,
                              style: TenturaText.body(tt.textMuted),
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        children: [
                          for (final m in state.messages)
                            _LobbyMessageTile(
                              message: m,
                              canBan:
                                  state.isAuthor &&
                                  m.authorId != widget.myUserId &&
                                  !state.bannedUserIds.contains(m.authorId),
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
                        decoration: InputDecoration(
                          hintText: l10n.beaconLobbyComposerHint,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('beaconLobbySend'),
                      tooltip: l10n.beaconLobbySend,
                      icon: const Icon(Icons.send),
                      onPressed: state.sending
                          ? null
                          : () => unawaited(cubit.post(_composer.text)),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One lobby message: a deliberately light version of the room message tile
/// (author, text, and the author's remove action).
class _LobbyMessageTile extends StatelessWidget {
  const _LobbyMessageTile({
    required this.message,
    required this.canBan,
    required this.onBan,
  });

  final BeaconLobbyMessage message;
  final bool canBan;
  final VoidCallback onBan;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(message.authorName),
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
