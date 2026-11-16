import 'dart:math';

import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/baton_selection_policy.dart';

RoomBatonCandidate _c(
  String userId, {
  int tier = 1,
  BatonResponse response = BatonResponse.canHelp,
  String? partner,
  BatonPartnerResponse? partnerResponse,
  DateTime? at,
}) => RoomBatonCandidate(
  batonId: 'L1',
  userId: userId,
  tier: tier,
  response: response,
  respondedAt: at,
  partnerUserId: partner,
  partnerResponse: partnerResponse,
);

const _acc = BatonPartnerResponse.accepted;

void main() {
  group('BatonSelectionPolicy with pairs', () {
    test('a pending pair is not eligible for pick or pickManual', () {
      final rows = [
        _c('A', partner: 'X', partnerResponse: BatonPartnerResponse.pending),
        _c('B', response: BatonResponse.cantHelp),
      ];
      expect(
        () => BatonSelectionPolicy.pick(rows, random: Random(1)),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
      for (final id in ['A', 'X']) {
        expect(
          () => BatonSelectionPolicy.pickManual(rows, id),
          throwsA(isA<BatonTakerNotAvailableException>()),
        );
      }
    });

    test('a pair is ranked by the inviter tier', () {
      final rows = [
        _c('A', tier: 2, partner: 'X', partnerResponse: _acc),
        _c('B', tier: 3),
      ];
      for (var s = 0; s < 20; s++) {
        final p = BatonSelectionPolicy.pick(rows, random: Random(s));
        expect((p.takerId, p.coTakerId), ('A', 'X'));
      }
    });

    test('a mutual pair is ranked by the lower tier of its members', () {
      final rows = [
        _c('A', tier: 3, partner: 'X', partnerResponse: _acc),
        _c('X', partner: 'A', partnerResponse: _acc),
        _c('B', tier: 2),
      ];
      for (var s = 0; s < 20; s++) {
        final p = BatonSelectionPolicy.pick(rows, random: Random(s));
        expect({p.takerId, p.coTakerId}, {'A', 'X'});
      }
    });

    test('pick draws a pair once, as one entry next to a solo candidate', () {
      final rows = [
        _c('B'),
        _c('A', partner: 'X', partnerResponse: _acc),
        _c('X', partner: 'A', partnerResponse: _acc),
      ];
      final random = Random(42);
      var solo = 0;
      var pair = 0;
      for (var i = 0; i < 1000; i++) {
        final p = BatonSelectionPolicy.pick(rows, random: random);
        if (p.takerId == 'B') {
          expect(p.coTakerId, isNull);
          solo++;
        } else {
          expect({p.takerId, p.coTakerId}, {'A', 'X'});
          pair++;
        }
      }
      expect(solo, greaterThan(400));
      expect(pair, greaterThan(400));
    });

    test('pickManual by either member of a one-sided pair', () {
      final rows = [_c('A', partner: 'X', partnerResponse: _acc)];
      for (final id in ['A', 'X']) {
        final p = BatonSelectionPolicy.pickManual(rows, id);
        expect((p.takerId, p.coTakerId), ('A', 'X'));
      }
    });

    test('pickManual on a mutual pair makes the earlier answer the taker', () {
      final rows = [
        _c('A', partner: 'X', partnerResponse: _acc, at: DateTime.utc(2026, 1, 1, 10)),
        _c('X', partner: 'A', partnerResponse: _acc, at: DateTime.utc(2026, 1, 1, 10, 5)),
      ];
      for (final id in ['A', 'X']) {
        final p = BatonSelectionPolicy.pickManual(rows, id);
        expect((p.takerId, p.coTakerId), ('A', 'X'));
      }
      // Reversed list order and reversed times: the earlier answer (X) wins.
      final flipped = [
        _c('A', partner: 'X', partnerResponse: _acc, at: DateTime.utc(2026, 1, 1, 10, 5)),
        _c('X', partner: 'A', partnerResponse: _acc, at: DateTime.utc(2026, 1, 1, 10)),
      ];
      for (final id in ['A', 'X']) {
        final p = BatonSelectionPolicy.pickManual(flipped.reversed.toList(), id);
        expect((p.takerId, p.coTakerId), ('X', 'A'));
      }
    });

    test('pickManual on a solo candidate has no co-taker', () {
      final p = BatonSelectionPolicy.pickManual([_c('A')], 'A');
      expect(p.takerId, 'A');
      expect(p.coTakerId, isNull);
    });
  });
}
