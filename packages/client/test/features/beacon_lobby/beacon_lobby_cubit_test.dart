import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import 'fake_lobby_port.dart';

/// Request Questions (internally the lobby, U088), client state.
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

  test('an offerer opens the lobby and sees its messages', () async {
    final port = FakeLobbyPort(viewerId: 'Unina')
      ..messagesList.add(
        const BeaconLobbyMessage(
          id: 'M1',
          authorId: 'Uauthor',
          authorName: 'Anna',
          body: 'The 18th',
        ),
      );
    final c = cubitFor(port);
    await c.load();
    expect(c.state.isSuccess, isTrue);
    expect(c.state.unavailable, isFalse);
    expect(c.state.isAuthor, isFalse);
    expect([for (final m in c.state.messages) m.body], ['The 18th']);
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

  test('posting adds the message and clears the composer; a failed post '
      'shows the error and keeps the lobby', () async {
    final port = FakeLobbyPort(viewerId: 'Unina');
    final c = cubitFor(port);
    await c.load();
    await c.post('  Which Saturday?  ');
    expect([for (final m in c.state.messages) m.body], ['Which Saturday?']);
    expect(c.state.postedCount, 1);
    await c.post('   ');
    expect(port.calls.where((x) => x.startsWith('post')), hasLength(1));
    port.failNext = true;
    await c.post('again');
    expect(c.state.postedCount, 1);
    expect(effects.emitted.single, isA<ShowError>());
    expect(c.state.info, isNotNull);
    await c.close();
  });

  test('no posting once the Request is closed (canPost false)', () async {
    final port = FakeLobbyPort(viewerId: 'Unina')..canPost = false;
    final c = cubitFor(port);
    await c.load();
    await c.post('late question');
    expect(port.calls, isNot(contains('post late question')));
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

  test(
    "a removed person's earlier messages stay in the author's lobby",
    () async {
      final port = FakeLobbyPort(viewerId: 'Uauthor');
      port.messagesList.add(
        const BeaconLobbyMessage(
          id: 'M0',
          authorId: 'Unina',
          authorName: 'Nina',
          body: 'I can bring a ladder',
        ),
      );
      final c = cubitFor(port);
      await c.load();
      await c.ban('Unina');
      expect([for (final b in c.state.banned) b.userId], ['Unina']);
      expect(
        [for (final m in c.state.messages) m.body],
        ['I can bring a ladder'],
      );
      await c.close();
    },
  );

  test('a message hint refetches the newest page only (no access '
      're-check); an offer hint re-opens', () async {
    final port = FakeLobbyPort(viewerId: 'Uauthor');
    final c = cubitFor(port);
    await c.load();
    int count(String call) => port.calls.where((x) => x == call).length;
    final opens = count('open');
    final pages = count('messages');
    port.messagesList.add(
      BeaconLobbyMessage(
        id: 'M9',
        authorId: 'Unina',
        authorName: 'Nina',
        body: 'Is there a lift?',
        createdAt: DateTime.utc(2026, 2),
      ),
    );
    sync.hint(RealtimeEntityKind.roomMessage, 'Bother');
    await settle();
    expect(count('messages'), pages);
    sync.hint(RealtimeEntityKind.roomMessage, 'B1');
    await settle();
    await settle();
    expect(count('open'), opens);
    expect(count('messages'), pages + 1);
    expect([for (final m in c.state.messages) m.body], ['Is there a lift?']);
    sync.hint(RealtimeEntityKind.helpOffer, 'B1');
    await settle();
    await settle();
    expect(count('open'), opens + 1);
    await c.close();
  });

  test('pages back with beforeIso until the oldest message', () async {
    final port = FakeLobbyPort(viewerId: 'Unina');
    for (var i = 0; i < 120; i++) {
      port.messagesList.add(
        BeaconLobbyMessage(
          id: 'M$i',
          authorId: 'Uauthor',
          authorName: 'Anna',
          body: 'm$i',
          createdAt: DateTime.utc(2026).add(Duration(minutes: i)),
        ),
      );
    }
    final c = cubitFor(port);
    await c.load();
    expect(c.state.messages, hasLength(50));
    expect(c.state.messages.first.body, 'm70');
    expect(c.state.hasOlder, isTrue);
    await c.loadOlder();
    expect(c.state.messages, hasLength(100));
    expect(c.state.hasOlder, isTrue);
    await c.loadOlder();
    expect(c.state.messages, hasLength(120));
    expect(c.state.messages.first.body, 'm0');
    expect(c.state.hasOlder, isFalse);
    // A later message hint keeps the older pages loaded.
    sync.hint(RealtimeEntityKind.roomMessage, 'B1');
    await settle();
    await settle();
    expect(c.state.messages, hasLength(120));
    await c.close();
  });

  test('opening marks Questions seen', () async {
    final port = FakeLobbyPort(viewerId: 'Unina');
    final c = cubitFor(port);
    await c.load();
    await settle();
    expect(port.calls, contains('seen'));
    await c.close();
  });

  test('removed meanwhile: the next refetch locks the lobby', () async {
    final port = FakeLobbyPort(viewerId: 'Unina');
    final c = cubitFor(port);
    await c.load();
    port.banned.add('Unina');
    await c.refresh();
    expect(c.state.unavailable, isTrue);
    expect(c.state.messages, isEmpty);
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
