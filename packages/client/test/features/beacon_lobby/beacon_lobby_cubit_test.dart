import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';

import 'fake_lobby_gateway.dart';

/// U088 — the Request lobby, client state.
void main() {
  BeaconLobbyCubit cubitFor(FakeLobbyGateway g) => BeaconLobbyCubit(
    beaconId: 'B1',
    gateway: g,
    pollInterval: const Duration(hours: 1),
  );

  test('an offerer opens the lobby and sees its messages', () async {
    final g = FakeLobbyGateway(viewerId: 'Unina')
      ..messagesList.add(
        const BeaconLobbyMessage(
          id: 'M1',
          authorId: 'Uauthor',
          authorName: 'Anna',
          body: 'The 18th',
        ),
      );
    final c = cubitFor(g);
    await c.load();
    expect(c.state.status, BeaconLobbyStatus.ready);
    expect(c.state.isAuthor, isFalse);
    expect([for (final m in c.state.messages) m.body], ['The 18th']);
    await c.close();
  });

  test('someone without an offer gets "unavailable"', () async {
    final c = cubitFor(FakeLobbyGateway(viewerId: 'Ustranger'));
    await c.load();
    expect(c.state.status, BeaconLobbyStatus.unavailable);
    await c.close();
  });

  test('posting adds the message; a failed post keeps the lobby open', () async {
    final g = FakeLobbyGateway(viewerId: 'Unina');
    final c = cubitFor(g);
    await c.load();
    expect(await c.post('  Which Saturday?  '), isTrue);
    expect([for (final m in c.state.messages) m.body], ['Which Saturday?']);
    expect(await c.post('   '), isFalse);
    g.failNextAction = true;
    expect(await c.post('again'), isFalse);
    expect(c.state.actionFailed, isTrue);
    expect(c.state.status, BeaconLobbyStatus.ready);
    await c.close();
  });

  test('the author bans and lets back in; the banned list follows', () async {
    final g = FakeLobbyGateway(viewerId: 'Uauthor');
    final c = cubitFor(g);
    await c.load();
    await c.ban('Unina');
    expect(c.state.bannedUserIds, ['Unina']);
    await c.unban('Unina');
    expect(c.state.bannedUserIds, isEmpty);
    expect(g.calls, containsAllInOrder(['ban Unina', 'unban Unina']));
    await c.close();
  });

  test('a banned offerer is locked out on the next refresh', () async {
    final g = FakeLobbyGateway(viewerId: 'Unina');
    final c = cubitFor(g);
    await c.load();
    g.banned.add('Unina');
    await c.refresh();
    expect(c.state.status, BeaconLobbyStatus.unavailable);
    await c.close();
  });

  test('a non-author cannot ban (no call is made)', () async {
    final g = FakeLobbyGateway(viewerId: 'Unina', offerers: {'Unina', 'Uomar'});
    final c = cubitFor(g);
    await c.load();
    await c.ban('Uomar');
    expect(g.calls, isNot(contains('ban Uomar')));
    await c.close();
  });
}
