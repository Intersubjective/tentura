import 'dart:math';

import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/baton_selection_policy.dart';

RoomBatonCandidate _candidate({
  required String userId,
  required int tier,
  required BatonResponse response,
}) => RoomBatonCandidate(
  batonId: 'L1',
  userId: userId,
  tier: tier,
  response: response,
);

void main() {
  group('BatonSelectionPolicy.pick (auto)', () {
    test(
      'returns only can_help + admitted people from the lowest non-empty tier',
      () {
        final candidates = [
          _candidate(userId: 'A', tier: 1, response: BatonResponse.cantHelp),
          _candidate(userId: 'B', tier: 2, response: BatonResponse.canHelp),
          _candidate(userId: 'C', tier: 3, response: BatonResponse.canHelp),
        ];
        final picked = BatonSelectionPolicy.pick(candidates, random: Random(1));
        expect(picked.userId, 'B');
      },
    );

    test('with a seeded Random, 1000 picks over three equal tier-1 candidates each get > 250', () {
      final candidates = [
        _candidate(userId: 'A', tier: 1, response: BatonResponse.canHelp),
        _candidate(userId: 'B', tier: 1, response: BatonResponse.canHelp),
        _candidate(userId: 'C', tier: 1, response: BatonResponse.canHelp),
      ];
      final counts = <String, int>{'A': 0, 'B': 0, 'C': 0};
      final random = Random(42);
      for (var i = 0; i < 1000; i++) {
        final picked = BatonSelectionPolicy.pick(candidates, random: random);
        counts[picked.userId] = counts[picked.userId]! + 1;
      }
      for (final count in counts.values) {
        expect(count, greaterThan(250));
      }
    });

    test('no eligible person throws BatonTakerNotAvailableException', () {
      final candidates = [
        _candidate(userId: 'A', tier: 1, response: BatonResponse.waiting),
        _candidate(userId: 'B', tier: 1, response: BatonResponse.cantHelp),
      ];
      expect(
        () => BatonSelectionPolicy.pick(candidates),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
    });

    test('empty candidate list throws BatonTakerNotAvailableException', () {
      expect(
        () => BatonSelectionPolicy.pick(const []),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
    });
  });

  group('BatonSelectionPolicy.pickManual', () {
    final candidates = [
      _candidate(userId: 'A', tier: 1, response: BatonResponse.waiting),
      _candidate(userId: 'B', tier: 2, response: BatonResponse.cantHelp),
      _candidate(userId: 'C', tier: 1, response: BatonResponse.canHelp),
    ];

    test('a can_help candidate is returned', () {
      final picked = BatonSelectionPolicy.pickManual(candidates, 'C');
      expect(picked.userId, 'C');
    });

    test('a waiting candidate throws BatonTakerNotAvailableException', () {
      expect(
        () => BatonSelectionPolicy.pickManual(candidates, 'A'),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
    });

    test('a cant_help candidate throws BatonTakerNotAvailableException', () {
      expect(
        () => BatonSelectionPolicy.pickManual(candidates, 'B'),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
    });

    test('a non-admitted (unlisted) user throws BatonTakerNotAvailableException', () {
      expect(
        () => BatonSelectionPolicy.pickManual(candidates, 'Z'),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
    });
  });

  group('BatonSelectionPolicy.validateCandidates', () {
    const authorId = 'Author1';
    const admitted = {'A', 'B', 'C'};

    void expectInvalid(List<({String userId, int tier})> candidates) {
      expect(
        () => BatonSelectionPolicy.validateCandidates(
          authorId: authorId,
          candidates: candidates,
          admittedIds: admitted,
        ),
        throwsA(isA<BatonInvalidCandidatesException>()),
      );
    }

    test('accepts 1..12 admitted, non-author, distinct candidates with valid tiers', () {
      BatonSelectionPolicy.validateCandidates(
        authorId: authorId,
        candidates: const [(userId: 'A', tier: 1), (userId: 'B', tier: 3)],
        admittedIds: admitted,
      );
    });

    test('rejects 0 candidates', () => expectInvalid(const []));

    test('rejects more than 12 candidates', () {
      final tooMany = [
        for (var i = 0; i < 13; i++) (userId: 'U$i', tier: 1),
      ];
      expect(
        () => BatonSelectionPolicy.validateCandidates(
          authorId: authorId,
          candidates: tooMany,
          admittedIds: {for (final c in tooMany) c.userId},
        ),
        throwsA(isA<BatonInvalidCandidatesException>()),
      );
    });

    test('rejects a duplicate candidate', () {
      expectInvalid(const [(userId: 'A', tier: 1), (userId: 'A', tier: 2)]);
    });

    test('rejects the author as a candidate', () {
      expectInvalid(const [(userId: authorId, tier: 1)]);
    });

    test('rejects a non-admitted user', () {
      expectInvalid(const [(userId: 'Z', tier: 1)]);
    });

    test('rejects a tier outside 1..3', () {
      expectInvalid(const [(userId: 'A', tier: 0)]);
      expectInvalid(const [(userId: 'A', tier: 4)]);
    });
  });

  test('exception codes are unique and >= 1322', () {
    const codes = [
      BeaconExceptionCode.batonNotFound,
      BeaconExceptionCode.batonNotAuthor,
      BeaconExceptionCode.batonNotCandidate,
      BeaconExceptionCode.batonNotCollecting,
      BeaconExceptionCode.batonInvalidCandidates,
      BeaconExceptionCode.batonAlreadyActive,
      BeaconExceptionCode.batonTakerNotAvailable,
      BeaconExceptionCode.batonMessageNotEligible,
    ];
    final numbers = codes.map((c) => BeaconExceptionCodes(c).codeNumber).toSet();
    expect(numbers.length, codes.length, reason: 'codes must be unique');
    expect(numbers.every((n) => n >= 1322), isTrue);
  });
}
