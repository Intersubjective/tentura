import 'dart:math';

import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/baton_pair_policy.dart';

final _now = DateTime.utc(2026, 1, 1, 12);

RoomBatonCandidate _row(
  String userId, {
  BatonResponse response = BatonResponse.waiting,
  String? partner,
  BatonPartnerResponse? partnerResponse,
  int invites = 0,
  int tier = 1,
}) => RoomBatonCandidate(
  batonId: 'L1',
  userId: userId,
  tier: tier,
  response: response,
  partnerUserId: partner,
  partnerResponse: partnerResponse,
  partnerInvites: invites,
);

RoomBatonCandidate _of(BatonPairResult r, String id) =>
    r.rows.singleWhere((c) => c.userId == id);

List<BatonPairReceipt> _to(BatonPairResult r, String id) =>
    r.receipts.where((x) => x.recipientId == id).toList();

BatonPairResult _respond(
  List<RoomBatonCandidate> rows,
  String actor, {
  bool canHelp = true,
  String? partner,
}) => BatonPairPolicy.respond(
  rows: rows,
  actorId: actor,
  canHelp: canHelp,
  partnerUserId: partner,
  now: _now,
);

void main() {
  group('BatonPairPolicy.respond', () {
    test('naming someone who named me back accepts both sides silently', () {
      final rows = [
        _row(
          'X',
          response: BatonResponse.canHelp,
          partner: 'A',
          partnerResponse: BatonPartnerResponse.pending,
        ),
        _row('A'),
      ];
      final r = _respond(rows, 'A', partner: 'X');
      for (final (id, other) in [('A', 'X'), ('X', 'A')]) {
        final row = _of(r, id);
        expect(row.response, BatonResponse.canHelp);
        expect(row.partnerUserId, other);
        expect(row.partnerResponse, BatonPartnerResponse.accepted);
      }
      expect(_to(r, 'X'), isEmpty);
      expect(r.receipts, hasLength(1));
      expect(r.receipts.single.recipientId, 'A');
      expect(r.receipts.single.kind, BatonPairReceiptKind.partnerAnswered);
      expect(r.receipts.single.accepted, isTrue);
    });

    test('naming a partner who named nobody sends one invitation', () {
      final r = _respond([_row('A'), _row('X')], 'A', partner: 'X');
      final a = _of(r, 'A');
      expect(a.response, BatonResponse.canHelp);
      expect(a.partnerUserId, 'X');
      expect(a.partnerResponse, BatonPartnerResponse.pending);
      expect(a.partnerInvites, 1);
      expect(r.receipts, hasLength(1));
      expect(r.receipts.single.kind, BatonPairReceiptKind.partnerAsked);
      expect(r.receipts.single.recipientId, 'X');
      expect(r.receipts.single.key, 'baton_partner_asked:L1:A:X');
    });

    test('the partner may be someone who is not a candidate', () {
      final r = _respond([_row('A')], 'A', partner: 'X');
      expect(_of(r, 'A').partnerUserId, 'X');
      expect(r.receipts.single.recipientId, 'X');
    });

    test('a fourth distinct partner is rejected', () {
      final rows = [
        _row(
          'A',
          response: BatonResponse.canHelp,
          partner: 'P3',
          partnerResponse: BatonPartnerResponse.declined,
          invites: 3,
        ),
      ];
      expect(
        () => _respond(rows, 'A', partner: 'P4'),
        throwsA(isA<BatonPartnerInvalidException>()),
      );
    });

    test('a third distinct partner is still allowed', () {
      final rows = [
        _row(
          'A',
          response: BatonResponse.canHelp,
          partner: 'P2',
          partnerResponse: BatonPartnerResponse.declined,
          invites: 2,
        ),
      ];
      final a = _of(_respond(rows, 'A', partner: 'P3'), 'A');
      expect(a.partnerUserId, 'P3');
      expect(a.partnerInvites, 3);
    });

    test('re-naming the current partner keeps the count and does not throw', () {
      final rows = [
        _row(
          'A',
          response: BatonResponse.canHelp,
          partner: 'X',
          partnerResponse: BatonPartnerResponse.pending,
          invites: 3,
        ),
      ];
      final r = _respond(rows, 'A', partner: 'X');
      expect(_of(r, 'A').partnerInvites, 3);
    });

    test("a partner cannot be named together with can't help", () {
      expect(
        () => _respond([_row('A')], 'A', canHelp: false, partner: 'X'),
        throwsA(isA<BatonPartnerInvalidException>()),
      );
    });

    test('naming yourself is rejected', () {
      expect(
        () => _respond([_row('A')], 'A', partner: 'A'),
        throwsA(isA<BatonPartnerInvalidException>()),
      );
    });

    test('answering solo clears the partner marker', () {
      final rows = [
        _row(
          'A',
          response: BatonResponse.canHelp,
          partner: 'X',
          partnerResponse: BatonPartnerResponse.pending,
          invites: 1,
        ),
      ];
      final a = _of(_respond(rows, 'A'), 'A');
      expect(a.response, BatonResponse.canHelp);
      expect(a.partnerUserId, isNull);
      expect(a.partnerResponse, isNull);
    });
  });

  group('BatonPairPolicy.partnerRespond', () {
    test('accepting a second invitation releases the first pair', () {
      final rows = [
        _row(
          'B',
          response: BatonResponse.canHelp,
          partner: 'Y',
          partnerResponse: BatonPartnerResponse.accepted,
        ),
        _row(
          'A',
          response: BatonResponse.canHelp,
          partner: 'Y',
          partnerResponse: BatonPartnerResponse.pending,
        ),
      ];
      final r = BatonPairPolicy.partnerRespond(
        rows: rows,
        actorId: 'Y',
        inviterId: 'A',
        accept: true,
        now: _now,
      );
      expect(_of(r, 'A').partnerResponse, BatonPartnerResponse.accepted);
      expect(_of(r, 'A').partnerUserId, 'Y');
      final b = _of(r, 'B');
      expect(b.response, BatonResponse.waiting);
      expect(b.partnerResponse, BatonPartnerResponse.declined);
      final toB = _to(r, 'B');
      expect(toB, hasLength(1));
      expect(toB.single.kind, BatonPairReceiptKind.partnerAnswered);
      expect(toB.single.accepted, isFalse);
      expect(
        r.rows.where(
          (c) =>
              c.partnerUserId == 'Y' &&
              c.partnerResponse == BatonPartnerResponse.accepted,
        ),
        hasLength(1),
      );
    });

    test('declining sends the inviter back to waiting and tells them', () {
      final rows = [
        _row(
          'A',
          response: BatonResponse.canHelp,
          partner: 'X',
          partnerResponse: BatonPartnerResponse.pending,
        ),
      ];
      final r = BatonPairPolicy.partnerRespond(
        rows: rows,
        actorId: 'X',
        inviterId: 'A',
        accept: false,
        now: _now,
      );
      final a = _of(r, 'A');
      expect(a.response, BatonResponse.waiting);
      expect(a.partnerResponse, BatonPartnerResponse.declined);
      expect(r.receipts.single.recipientId, 'A');
      expect(r.receipts.single.accepted, isFalse);
    });

    test('answering an invitation nobody made throws BatonNotPartnerException', () {
      expect(
        () => BatonPairPolicy.partnerRespond(
          rows: [_row('A', response: BatonResponse.canHelp)],
          actorId: 'X',
          inviterId: 'A',
          accept: true,
          now: _now,
        ),
        throwsA(isA<BatonNotPartnerException>()),
      );
    });
  });

  test('random action sequences keep one accepted pair per person', () {
    final ids = List.generate(6, (i) => 'U$i');
    final random = Random(7);
    var acceptedPairsSeen = 0;
    var releasesSeen = 0;
    for (var seq = 0; seq < 500; seq++) {
      var rows = [for (final id in ids) _row(id)];
      var changed = 0;
      for (var step = 0; step < 25; step++) {
        final actor = ids[random.nextInt(ids.length)];
        try {
          if (random.nextBool()) {
            final kind = random.nextInt(3);
            String? partner;
            if (kind == 2) {
              final others = ids.where((i) => i != actor).toList();
              partner = others[random.nextInt(others.length)];
            }
            rows = _respond(
              rows,
              actor,
              canHelp: kind != 1,
              partner: partner,
            ).rows;
          } else {
            final inviter = ids[random.nextInt(ids.length)];
            rows = BatonPairPolicy.partnerRespond(
              rows: rows,
              actorId: actor,
              inviterId: inviter,
              accept: random.nextBool(),
              now: _now,
            ).rows;
          }
          changed++;
        } on BatonPartnerInvalidException {
          // rejected action
        } on BatonNotPartnerException {
          // rejected action
        }
        if (rows.any(
          (c) => c.partnerResponse == BatonPartnerResponse.accepted,
        )) {
          acceptedPairsSeen++;
        }
        if (rows.any(
          (c) =>
              c.partnerResponse == BatonPartnerResponse.declined &&
              c.response == BatonResponse.waiting,
        )) {
          releasesSeen++;
        }
        final pairs = <String, Set<String>>{};
        for (final c in rows) {
          if (c.partnerUserId != null) {
            expect(c.response, BatonResponse.canHelp, reason: 'seq $seq');
          }
          if (c.partnerResponse == BatonPartnerResponse.accepted) {
            final pair = {c.userId, c.partnerUserId!}.toList()..sort();
            for (final m in pair) {
              pairs.putIfAbsent(m, () => {}).add(pair.join('|'));
            }
          }
        }
        for (final e in pairs.entries) {
          expect(e.value, hasLength(1), reason: 'seq $seq user ${e.key}');
        }
      }
      expect(changed, greaterThan(0));
    }
    expect(acceptedPairsSeen, greaterThan(100), reason: 'pairs must form');
    expect(releasesSeen, greaterThan(100), reason: 'pairs must be released');
  });
}
