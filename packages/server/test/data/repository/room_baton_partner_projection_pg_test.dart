@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/room_baton_repository.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Ubatontg_au1';
const _a = 'Ubatontg_ca1';
const _b = 'Ubatontg_cb1';
const _c = 'Ubatontg_cc1';
const _x = 'Ubatontg_px1';
const _y = 'Ubatontg_py1';
const _observer = 'Ubatontg_ob1';

const _request = 'Bbatontg_rq1';
const _message = 'Rbatontg_rq1';
const _plainMessage = 'Rbatontg_pl1';
const _batonId = 'Lbatontg_ba1';

const _titles = <String, String>{
  _author: 'Author Name',
  _a: 'Alice Name',
  _b: 'Bob Name',
  _c: 'Carol Name',
  _x: 'Xenia Name',
  _y: 'Yuri Name',
  _observer: 'Olga Name',
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_BATON_PARTNER_PROJECTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_baton_partner_projection',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('viewer-specific baton data with partners', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late BeaconRoomRepository room;
    late RoomBatonRepository batons;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      room = BeaconRoomRepository(database);
      batons = RoomBatonRepository(database);
    });

    setUp(() => _resetFixture(writer));

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    Future<String?> rawFor(String viewer, [String messageId = _message]) async {
      final rows = await room.listMessagesEnriched(
        beaconId: _request,
        viewerUserId: viewer,
      );
      return rows.singleWhere((r) => r['id'] == messageId)['batonDataJson']
          as String?;
    }

    Future<Map<String, Object?>> payloadFor(String viewer) async {
      final raw = await rawFor(viewer);
      expect(raw, isNotNull, reason: 'viewer $viewer must get baton data');
      return (jsonDecode(raw!) as Map).cast<String, Object?>();
    }

    Future<void> create(Map<String, int> tiers) => batons.create(
      id: _batonId,
      messageId: _message,
      beaconId: _request,
      authorId: _author,
      candidates: [
        for (final e in tiers.entries) (userId: e.key, tier: e.value),
      ],
    );

    Future<void> setRow(
      String user, {
      required int response,
      String? partner,
      int? partnerResponse,
    }) => writer.execute(
      Sql.named('''
UPDATE public.beacon_room_baton_candidate
   SET response = @r, partner_user_id = @p, partner_response = @pr,
       partner_invites = @n
 WHERE baton_id = '$_batonId' AND user_id = @u
'''),
      parameters: {
        'r': response,
        'p': partner,
        'pr': partnerResponse,
        'n': partner == null ? 0 : 1,
        'u': user,
      },
    );

    /// A (tier 1, partner X pending), B (tier 2, partner Y accepted,
    /// Y not a candidate), C (tier 1, solo).
    Future<void> collecting() async {
      await create({_a: 1, _b: 2, _c: 1});
      await setRow(_a, response: 1, partner: _x, partnerResponse: 0);
      await setRow(_b, response: 1, partner: _y, partnerResponse: 1);
      await setRow(_c, response: 1);
    }

    Future<void> select(String taker, {String? coTaker}) => batons.select(
      batonId: _batonId,
      takerId: taker,
      mode: BatonSelectionMode.manual,
      resolvedAt: DateTime.utc(2026, 10, 2, 12),
      coTakerId: coTaker,
    );

    void expectNoLeakOf(String raw, Iterable<String> others) {
      for (final other in others) {
        expect(raw, isNot(contains(other)), reason: 'id of $other leaked');
        expect(
          raw,
          isNot(contains(_titles[other])),
          reason: 'title of $other leaked',
        );
      }
    }

    Map<String, Object?> candidateRow(Map<String, Object?> p, String id) =>
        (p['candidates']! as List)
            .cast<Map<String, Object?>>()
            .singleWhere((c) => c['userId'] == id);

    test('author sees pending partner hidden, accepted partner and pairs',
        () async {
      await collecting();
      final p = await payloadFor(_author);

      expect(p['viewerRole'], 'author');
      final a = candidateRow(p, _a);
      expect(a['response'], 'waiting');
      expect(a.containsKey('partner'), isFalse);
      final b = candidateRow(p, _b);
      expect(b['response'], 'can_help');
      expect(b['partner'], {'id': _y, 'title': _titles[_y]});
      expect(candidateRow(p, _c).containsKey('partner'), isFalse);
      expect(p['pairs'], [
        {'takerId': _b, 'partnerId': _y, 'tier': 2},
      ]);
      expect(p['eligibleCount'], 2);
      final raw = await rawFor(_author);
      expect(raw, isNot(contains(_x)), reason: 'pending partner id leaked');
      expect(
        raw,
        isNot(contains(_titles[_x])),
        reason: 'pending partner title leaked',
      );
    });

    test('partner sees only their invitation while collecting', () async {
      await collecting();
      final px = await payloadFor(_x);
      expect(px['viewerRole'], 'partner');
      expect(px['status'], 'collecting');
      expect(px.containsKey('outcome'), isFalse);
      expect(px['partnerInvites'], [
        {'fromUserId': _a, 'title': _titles[_a], 'status': 'pending'},
      ]);
      final py = await payloadFor(_y);
      expect(py['viewerRole'], 'partner');
      expect(py['partnerInvites'], [
        {'fromUserId': _b, 'title': _titles[_b], 'status': 'accepted'},
      ]);

      for (final (raw, others) in [
        (await rawFor(_x), [_b, _c, _y]),
        (await rawFor(_y), [_a, _c, _x]),
      ]) {
        for (final key in [
          'candidates',
          'pairs',
          'eligibleCount',
          'tier',
          'allAnswered',
        ]) {
          expect(raw, isNot(contains('"$key"')), reason: '$key leaked');
        }
        expectNoLeakOf(raw!, others);
      }
    });

    test('candidate sees own partner and nobody else', () async {
      await collecting();
      final pa = await payloadFor(_a);
      expect(pa['viewerRole'], 'candidate');
      expect(pa['myPartner'], {
        'id': _x,
        'title': _titles[_x],
        'status': 'pending',
      });
      final pb = await payloadFor(_b);
      expect(pb['myPartner'], {
        'id': _y,
        'title': _titles[_y],
        'status': 'accepted',
      });
      expect((await payloadFor(_c)).containsKey('myPartner'), isFalse);
      expectNoLeakOf((await rawFor(_a))!, [_b, _c, _y]);
      expectNoLeakOf((await rawFor(_b))!, [_a, _c, _x]);
    });

    test('mutual pair: invite shows on the other candidate, counted once',
        () async {
      await create({_a: 2, _c: 1});
      await setRow(_a, response: 1, partner: _c, partnerResponse: 1);
      await setRow(_c, response: 1, partner: _a, partnerResponse: 1);

      final pc = await payloadFor(_c);
      expect(pc['partnerInvites'], [
        {'fromUserId': _a, 'title': _titles[_a], 'status': 'accepted'},
      ]);
      final author = await payloadFor(_author);
      final pairs = (author['pairs']! as List).cast<Map<String, Object?>>();
      expect(pairs, hasLength(1));
      expect({pairs.single['takerId'], pairs.single['partnerId']}, {_a, _c});
      expect(pairs.single['tier'], 1);
      expect(author['eligibleCount'], 1);
    });

    test('after selecting a pair the room sees both takers', () async {
      await collecting();
      await select(_b, coTaker: _y);

      final o = await payloadFor(_observer);
      expect(o['viewerRole'], 'observer');
      expect(o['status'], 'taken');
      expect(o['taker'], {'id': _b, 'title': _titles[_b]});
      expect(o['coTaker'], {'id': _y, 'title': _titles[_y]});
      final au = await payloadFor(_author);
      expect(au['taker'], {'id': _b, 'title': _titles[_b]});
      expect(au['coTaker'], {'id': _y, 'title': _titles[_y]});
      final pb = await payloadFor(_b);
      expect(pb['outcome'], 'you');
      expect(pb['taker'], {'id': _b, 'title': _titles[_b]});
      expect(pb['coTaker'], {'id': _y, 'title': _titles[_y]});
      final py = await payloadFor(_y);
      expect(py['viewerRole'], 'partner');
      expect(py['outcome'], 'you');
      final px = await payloadFor(_x);
      expect(px['viewerRole'], 'observer');
      expect(px['taker'], {'id': _b, 'title': _titles[_b]});
      expect(px['coTaker'], {'id': _y, 'title': _titles[_y]});
      expect(px.containsKey('partnerInvites'), isFalse);
      expect(px.containsKey('outcome'), isFalse);
    });

    test('after selecting a solo taker the partner lost out', () async {
      await collecting();
      await select(_c);

      final py = await payloadFor(_y);
      expect(py['viewerRole'], 'partner');
      expect(py['outcome'], 'someoneElse');
      final o = await payloadFor(_observer);
      expect(o['taker'], {'id': _c, 'title': _titles[_c]});
      expect(o.containsKey('coTaker'), isFalse);
      expect((await payloadFor(_x))['viewerRole'], 'observer');
    });

    test('after cancel pending and accepted partners get closed', () async {
      await collecting();
      await batons.cancel(
        batonId: _batonId,
        resolvedAt: DateTime.utc(2026, 10, 2, 12),
      );

      final py = await payloadFor(_y);
      expect(py['viewerRole'], 'partner');
      expect(py['status'], 'cancelled');
      expect(py['outcome'], 'closed');
      final px = await payloadFor(_x);
      expect(px['viewerRole'], 'partner');
      expect(px['outcome'], 'closed');
    });

    test('declined invitation: candidate sees declined, partner is observer',
        () async {
      await create({_a: 1, _c: 1});
      await setRow(_a, response: 0, partner: _x, partnerResponse: 2);
      await setRow(_c, response: 1);

      final pa = await payloadFor(_a);
      expect((pa['myPartner']! as Map)['status'], 'declined');
      final au = await payloadFor(_author);
      final a = candidateRow(au, _a);
      expect(a['response'], 'waiting');
      expect(a.containsKey('partner'), isFalse);
      expect((await payloadFor(_x))['viewerRole'], 'observer');
    });

    test('erased partner reads as declined and is hidden from the author',
        () async {
      await create({_a: 1, _c: 1});
      await setRow(_a, response: 1, partner: _x, partnerResponse: 0);
      await writer.execute(
        "DELETE FROM public.beacon_participant WHERE user_id = '$_x'",
      );
      await writer.execute("DELETE FROM public.\"user\" WHERE id = '$_x'");

      final au = await payloadFor(_author);
      final a = candidateRow(au, _a);
      expect(a['response'], 'waiting');
      expect(a.containsKey('partner'), isFalse);
      final pa = await payloadFor(_a);
      expect((pa['myPartner']! as Map)['status'], 'declined');
      final raw = await rawFor(_author);
      expect(raw, isNot(contains(_x)), reason: 'erased partner id leaked');
      expect(
        raw,
        isNot(contains(_titles[_x])),
        reason: 'erased partner title leaked',
      );
    });

    test('a message without a baton has no baton data for anyone', () async {
      await collecting();
      for (final v in [_author, _a, _x, _y, _observer]) {
        expect(await rawFor(v, _plainMessage), isNull);
      }
    });
  });
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.beacon_room_baton_candidate,
  public.beacon_room_baton,
  public.beacon_room_message,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_author, _a, _b, _c, _x, _y, _observer];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @title, @key)
'''),
      parameters: {
        'id': users[i],
        'title': _titles[users[i]],
        'key': pgTestPublicKey('batontg', i + 1),
      },
    );
  }
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES ('$_request', '$_author', 'Request', '', 0, now())
''');
  var n = 0;
  for (final user in users) {
    await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pbatontg${(n++).toString().padLeft(3, '0')}', '$_request', '$user', 0, 0, 3)
''');
  }
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  ('$_message', '$_request', '$_author', 'Can someone take this?'),
  ('$_plainMessage', '$_request', '$_author', 'Just a note')
''');
}
