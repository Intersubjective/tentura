import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';

import 'fake_lobby_port.dart';

/// The lobby's background re-open and its unavailable-reason probe keep
/// swallowing a failure (what is on screen stays), and now log it.
class _AccessFailsLobbyPort extends FakeLobbyPort {
  _AccessFailsLobbyPort({required super.viewerId});

  @override
  Future<BeaconLobbyAccess> access(String beaconId) async {
    calls.add('access');
    throw Exception('probe down');
  }
}

void main() {
  late FakeRealtimeSyncPort sync;
  late RecordingEffects effects;
  late List<LogRecord> records;
  late Level rootLevel;

  setUp(() {
    sync = FakeRealtimeSyncPort();
    effects = RecordingEffects();
    records = [];
    rootLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord
        .where((r) => r.loggerName == 'BeaconLobbyCubit')
        .listen(records.add);
    addTearDown(sub.cancel);
  });

  tearDown(() async {
    Logger.root.level = rootLevel;
    await sync.dispose();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a failed background re-open is logged as a warning; the screen '
      'keeps what it showed and no error is surfaced', () async {
    final port = FakeLobbyPort(viewerId: 'Unina');
    final c = BeaconLobbyCubit(
      lobbyCaseFor(port, sync),
      effects,
      beaconId: 'B1',
    );
    addTearDown(c.close);
    await c.load();
    final before = c.state;
    expect(before.info?.lobbyId, 'Llobby');

    port.failNext = true;
    sync.hint(RealtimeEntityKind.participant, 'B1');
    await settle();
    await settle();

    final refresh = records.where((r) => r.message == 'Lobby refresh failed');
    expect(refresh, hasLength(1));
    expect(refresh.single.level, Level.WARNING);
    expect(refresh.single.error, isA<Exception>());
    expect(c.state, before);
    expect(effects.emitted, isEmpty);
  });

  test('a failed unavailable-reason probe is logged at fine; the generic '
      'unavailable message stays', () async {
    final port = _AccessFailsLobbyPort(viewerId: 'Ustranger');
    final c = BeaconLobbyCubit(
      lobbyCaseFor(port, sync),
      effects,
      beaconId: 'B1',
    );
    addTearDown(c.close);
    await c.load();
    await settle();
    await settle();

    expect(port.calls, contains('access'));
    final probe = records.where(
      (r) => r.message == 'Lobby unavailable-reason probe failed',
    );
    expect(probe, hasLength(1));
    expect(probe.single.level, Level.FINE);
    expect(c.state.unavailable, isTrue);
    expect(c.state.unavailableReason, isNull);
    expect(c.state.loadError, isNull);
    expect(effects.emitted, isEmpty);
  });
}
