import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/policy/room_access_policy.dart';

// RoomAccessPolicy.canUseRoom is the gate BeaconRoomCase and RoomBatonCase
// share: author, then a Post-author block, then steward, then admitted; each
// fact is read only when the ones before do not decide.
void main() {
  Future<({bool allowed, List<String> read})> run({
    bool author = false,
    bool blocked = false,
    bool steward = false,
    int? access,
  }) async {
    final read = <String>[];
    Future<T> fact<T>(String name, T value) async {
      read.add(name);
      return value;
    }

    final allowed = await RoomAccessPolicy.canUseRoom(
      isAuthor: () => fact('author', author),
      isBlockedFromPost: () => fact('blocked', blocked),
      isSteward: () => fact('steward', steward),
      roomAccess: () => fact('access', access),
    );
    return (allowed: allowed, read: read);
  }

  test('the author is allowed without reading anything else', () async {
    final r = await run(author: true, blocked: true);
    expect(r.allowed, isTrue);
    expect(r.read, ['author']);
  });

  test('a block refuses before steward and admission', () async {
    final r = await run(
      blocked: true,
      steward: true,
      access: RoomAccessBits.admitted,
    );
    expect(r.allowed, isFalse);
    expect(r.read, ['author', 'blocked']);
  });

  test('a steward is allowed without a participant row', () async {
    final r = await run(steward: true);
    expect(r.allowed, isTrue);
    expect(r.read, ['author', 'blocked', 'steward']);
  });

  test('otherwise only an admitted participant is allowed', () async {
    expect((await run(access: RoomAccessBits.admitted)).allowed, isTrue);
    expect((await run()).allowed, isFalse);
    final notAdmitted = await run(access: RoomAccessBits.admitted + 1);
    expect(notAdmitted.allowed, isFalse);
    expect(notAdmitted.read, ['author', 'blocked', 'steward', 'access']);
  });
}
