import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import 'fake_lobby_port.dart';

/// Request Questions (internally the lobby, U088), client state: the
/// viewer's standing and the author's removals (the messages are the room
/// chat's).
void main() {
  late FakeRealtimeSyncPort sync;
  late RecordingEffects effects;

  setUp(() {
    sync = FakeRealtimeSyncPort();
    effects = RecordingEffects();
  });

  tearDown(() => sync.dispose());

  BeaconLobbyCubit cubitFor(FakeLobbyPort port) =>
      BeaconLobbyCubit(lobbyCaseFor(port, sync), effects, beaconId: 'B1');

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('an offerer opens Questions and may post', () async {
    final c = cubitFor(FakeLobbyPort(viewerId: 'Unina'));
    await c.load();
    expect(c.state.isSuccess, isTrue);
    expect(c.state.unavailable, isFalse);
    expect(c.state.isAuthor, isFalse);
    expect(c.state.canPost, isTrue);
    expect(c.state.info?.lobbyId, 'Llobby');
    await c.close();
  });

  test('someone the server keeps out sees "unavailable"', () async {
    final c = cubitFor(FakeLobbyPort(viewerId: 'Ustranger'));
    await c.load();
    expect(c.state.unavailable, isTrue);
    expect(c.state.loadError, isNull);
    await c.close();
  });

  test('a network error shows a retry, not the access message', () async {
    final port = FakeLobbyPort(viewerId: 'Unina')..failNext = true;
    final c = cubitFor(port);
    await c.load();
    expect(c.state.unavailable, isFalse);
    expect(c.state.loadError, isNotNull);
    await c.load();
    expect(c.state.loadError, isNull);
    expect(c.state.info?.lobbyId, 'Llobby');
    await c.close();
  });

  test('removed while the screen is open: the next standing hint says "the '
      'author removed you", not an error bar (#683)', () async {
    final port = FakeLobbyPort(viewerId: 'Unina');
    final c = cubitFor(port);
    await c.load();
    expect(c.state.canPost, isTrue);
    port
      ..banned.add('Unina')
      ..limitReason = BeaconLobbyLimitReason.removed;
    sync.hint(RealtimeEntityKind.participant, 'B1');
    await settle();
    await settle();
    expect(effects.emitted, isEmpty);
    expect(c.state.unavailable, isTrue);
    expect(c.state.unavailableReason, BeaconLobbyLimitReason.removed);
    await c.close();
  });

  test(
    'no longer allowed to ask while the screen is open (offer declined): '
    'the next standing hint makes it read-only and names why (#683)',
    () async {
      final port = FakeLobbyPort(viewerId: 'Unina');
      final c = cubitFor(port);
      await c.load();
      expect(c.state.canPost, isTrue);
      port
        ..canPost = false
        ..limitReason = BeaconLobbyLimitReason.declined;
      sync.hint(RealtimeEntityKind.helpOffer, 'B1');
      await settle();
      await settle();
      expect(effects.emitted, isEmpty);
      expect(c.state.unavailable, isFalse);
      expect(c.state.canPost, isFalse);
      expect(c.state.readOnlyReason, BeaconLobbyLimitReason.declined);
      await c.close();
    },
  );

  test('a message hint does not re-check the standing; a hint about '
      'another Request is ignored', () async {
    final port = FakeLobbyPort(viewerId: 'Uauthor');
    final c = cubitFor(port);
    await c.load();
    int opens() => port.calls.where((x) => x == 'open').length;
    final before = opens();
    sync
      ..hint(RealtimeEntityKind.roomMessage, 'B1')
      ..hint(RealtimeEntityKind.helpOffer, 'Bother');
    await settle();
    await settle();
    expect(opens(), before);
    await c.close();
  });

  test('the author removes and lets back in; the removed list follows; a '
      'failed removal shows the error', () async {
    final port = FakeLobbyPort(viewerId: 'Uauthor');
    final c = cubitFor(port);
    await c.load();
    await c.ban('Unina');
    expect([for (final b in c.state.banned) b.userId], ['Unina']);
    await c.unban('Unina');
    expect([for (final b in c.state.banned) b.userId], isEmpty);
    port.failNext = true;
    await c.ban('Unina');
    expect(effects.emitted.single, isA<ShowError>());
    expect([for (final b in c.state.banned) b.userId], isEmpty);
    await c.close();
  });

  test('a non-author cannot remove anyone (no call is made)', () async {
    final port = FakeLobbyPort(
      viewerId: 'Unina',
      offerers: {'Unina', 'Uomar'},
    );
    final c = cubitFor(port);
    await c.load();
    await c.ban('Uomar');
    expect(port.calls, isNot(contains('ban Uomar')));
    await c.close();
  });
}
