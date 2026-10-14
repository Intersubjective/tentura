import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/beacon_lobby_gateway.dart';
import '../../domain/entity/beacon_lobby.dart';
import '../bloc/beacon_lobby_cubit.dart';

/// Opens the lobby of [beaconId] as a full screen.
Future<void> openBeaconLobby(
  BuildContext context, {
  required String beaconId,
  required String myUserId,
  Map<String, String> knownNames = const {},
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => BeaconLobbyView(
      beaconId: beaconId,
      myUserId: myUserId,
      knownNames: knownNames,
    ),
  ),
);

/// U088 — the Request lobby: questions before helping, for the author and the
/// people with a live help offer. The author can remove someone from it.
class BeaconLobbyView extends StatelessWidget {
  const BeaconLobbyView({
    required this.beaconId,
    required this.myUserId,
    this.knownNames = const {},
    this.gateway,
    super.key,
  });

  final String beaconId;
  final String myUserId;

  /// Display names by user id (help offerers), for the removed list.
  final Map<String, String> knownNames;
  final BeaconLobbyGateway? gateway;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => BeaconLobbyCubit(
      beaconId: beaconId,
      gateway: gateway ?? GetIt.I<BeaconLobbyGateway>(),
    )..load(),
    child: _BeaconLobbyBody(myUserId: myUserId, knownNames: knownNames),
  );
}

class _BeaconLobbyBody extends StatefulWidget {
  const _BeaconLobbyBody({required this.myUserId, required this.knownNames});

  final String myUserId;
  final Map<String, String> knownNames;

  @override
  State<_BeaconLobbyBody> createState() => _BeaconLobbyBodyState();
}

class _BeaconLobbyBodyState extends State<_BeaconLobbyBody> {
  final _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  String _nameOf(String userId, BeaconLobbyState state) {
    final known = widget.knownNames[userId];
    if (known != null && known.isNotEmpty) return known;
    for (final m in state.messages) {
      if (m.authorId == userId && m.authorName.isNotEmpty) return m.authorName;
    }
    return userId;
  }

  Future<void> _confirmBan(
    BuildContext context,
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
    final cubit = context.read<BeaconLobbyCubit>();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.beaconLobbyTitle)),
      body: BlocConsumer<BeaconLobbyCubit, BeaconLobbyState>(
        listenWhen: (p, c) => !p.actionFailed && c.actionFailed,
        listener: (context, _) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.beaconLobbyActionFailed)),
        ),
        builder: (context, state) {
          switch (state.status) {
            case BeaconLobbyStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case BeaconLobbyStatus.unavailable:
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.beaconLobbyUnavailable,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => unawaited(cubit.load()),
                        child: Text(l10n.beaconLobbyRetry),
                      ),
                    ],
                  ),
                ),
              );
            case BeaconLobbyStatus.ready:
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      l10n.beaconLobbyEntrySubtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (state.isAuthor && state.bannedUserIds.isNotEmpty)
                    ExpansionTile(
                      key: const Key('beaconLobbyBannedFold'),
                      title: Text(
                        l10n.beaconLobbyBannedHeading(
                          state.bannedUserIds.length,
                        ),
                      ),
                      children: [
                        for (final id in state.bannedUserIds)
                          ListTile(
                            title: Text(_nameOf(id, state)),
                            trailing: TextButton(
                              onPressed: () => unawaited(cubit.unban(id)),
                              child: Text(l10n.beaconLobbyUnbanAction),
                            ),
                          ),
                      ],
                    ),
                  Expanded(
                    child: state.messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                l10n.beaconLobbyEmpty,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: [
                              for (final m in state.messages)
                                ListTile(
                                  title: Text(m.authorName),
                                  subtitle: Text(m.body),
                                  trailing:
                                      state.isAuthor &&
                                          m.authorId != widget.myUserId &&
                                          !state.bannedUserIds.contains(
                                            m.authorId,
                                          )
                                      ? IconButton(
                                          tooltip: l10n.beaconLobbyBanAction,
                                          icon: const Icon(
                                            Icons.person_remove_outlined,
                                          ),
                                          onPressed: () => unawaited(
                                            _confirmBan(
                                              context,
                                              cubit,
                                              m.authorId,
                                              m.authorName,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                            ],
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
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
                                : () async {
                                    final sent = await cubit.post(
                                      _composer.text,
                                    );
                                    if (sent) _composer.clear();
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
          }
        },
      ),
    );
  }
}
