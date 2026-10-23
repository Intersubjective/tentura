import 'dart:async';

import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/domain/exception/beacon_lobby_exception.dart';
import 'package:tentura/features/beacon_lobby/domain/port/beacon_lobby_port.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

/// In-memory Request Questions (internally the lobby, U088). The real
/// audience is the server policy; here a fixed set of readers stands in for
/// it, removed people are kept out, only the author removes.
class FakeLobbyPort implements BeaconLobbyPort {
  FakeLobbyPort({
    required this.viewerId,
    this.authorId = 'Uauthor',
    Set<String>? offerers,
  }) : offerers = offerers ?? {'Unina'};

  final String viewerId;
  final String authorId;
  final Set<String> offerers;
  final banned = <String>[];
  final messagesList = <BeaconLobbyMessage>[];
  final calls = <String>[];
  bool canPost = true;

  /// What the server would say about the viewer's own limit (#657).
  BeaconLobbyLimitReason? limitReason;

  /// The next call of any kind fails like a dropped connection.
  bool failNext = false;

  bool get _allowed =>
      viewerId == authorId ||
      (offerers.contains(viewerId) && !banned.contains(viewerId));

  void _maybeFail() {
    if (failNext) {
      failNext = false;
      throw Exception('network');
    }
  }

  @override
  Future<BeaconLobbyInfo> open(String beaconId) async {
    calls.add('open');
    _maybeFail();
    if (!_allowed) throw const BeaconLobbyUnavailableException();
    return BeaconLobbyInfo(
      beaconId: beaconId,
      lobbyId: 'Llobby',
      isAuthor: viewerId == authorId,
      canPost: canPost,
      authorId: authorId,
      readOnlyReason: canPost ? null : limitReason,
      banned: viewerId == authorId
          ? [
              for (final id in banned)
                BeaconLobbyBannedPerson(userId: id, name: 'Name of $id'),
            ]
          : const [],
    );
  }

  @override
  Future<BeaconLobbyAccess> access(String beaconId) async {
    calls.add('access');
    _maybeFail();
    return BeaconLobbyAccess(
      canRead: _allowed,
      canPost: _allowed && canPost,
      messageCount: _allowed ? messagesList.length : 0,
      limitReason: limitReason,
    );
  }

  /// Server page size.
  static const pageSize = 50;

  @override
  Future<List<BeaconLobbyMessage>> messages({
    required String beaconId,
    required String lobbyId,
    DateTime? before,
  }) async {
    calls.add(before == null ? 'messages' : 'messages before');
    if (!_allowed) throw const BeaconLobbyUnavailableException();
    final older = [
      for (final m in messagesList)
        if (before == null ||
            (m.createdAt != null && m.createdAt!.isBefore(before)))
          m,
    ];
    return older.length <= pageSize
        ? older
        : older.sublist(older.length - pageSize);
  }

  @override
  Future<void> markSeen({
    required String beaconId,
    required String lobbyId,
  }) async {
    calls.add('seen');
  }

  @override
  Future<void> post({
    required String beaconId,
    required String lobbyId,
    required String body,
  }) async {
    calls.add('post $body');
    _maybeFail();
    // The repository turns the room API's refusal (1102) into this (#683).
    if (!_allowed || !canPost) throw const BeaconLobbyPostDeniedException();
    messagesList.add(
      BeaconLobbyMessage(
        id: 'M${messagesList.length}',
        authorId: viewerId,
        authorName: viewerId == authorId ? 'Anna' : 'Nina',
        body: body,
        createdAt: DateTime.utc(2026).add(
          Duration(minutes: messagesList.length),
        ),
      ),
    );
  }

  @override
  Future<void> ban({required String beaconId, required String userId}) async {
    calls.add('ban $userId');
    _maybeFail();
    if (!banned.contains(userId)) banned.add(userId);
  }

  @override
  Future<void> unban({required String beaconId, required String userId}) async {
    calls.add('unban $userId');
    _maybeFail();
    banned.remove(userId);
  }
}

/// Realtime hints the test pushes by hand.
final class FakeRealtimeSyncPort implements RealtimeSyncPort {
  final _changes = StreamController<RealtimeEntityChange>.broadcast();
  final _catchUps = StreamController<RealtimeCatchUp>.broadcast();

  void hint(RealtimeEntityKind kind, String beaconId) => _changes.add(
    RealtimeEntityChange(
      kind: kind,
      aggregateId: beaconId,
      operation: RealtimeOperation.insert,
      source: RealtimeChangeSource.serverInvalidation,
    ),
  );

  @override
  Stream<RealtimeEntityChange> get entityChanges => _changes.stream;

  @override
  Stream<RealtimeCatchUp> get catchUps => _catchUps.stream;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      const Stream.empty();

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}

  @override
  Future<void> dispose() async {
    await _changes.close();
    await _catchUps.close();
  }
}

final class RecordingEffects implements UiEffectPort {
  final emitted = <UiEffect>[];

  @override
  void emit(UiEffect effect) => emitted.add(effect);

  @override
  Stream<UiEffect> get effects => const Stream.empty();
}

BeaconLobbyCase lobbyCaseFor(FakeLobbyPort port, FakeRealtimeSyncPort sync) =>
    BeaconLobbyCase(port, RealtimeSyncCase(sync));
