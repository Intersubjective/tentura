import 'dart:math';

import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/episode_settlement.dart';
import 'package:tentura_server/domain/closure/settlement_params.dart';

const _vectorTol = 1e-4;
const _impartialityTol = 1e-12;
const _conservationTol = 1e-9;
const _poolH = 0.7;

/// Flip to true once A7a vector and property expectations are accepted (tests-only).
const _a7aAcceptanceEnabled = true;

final _settlement = EpisodeSettlement();
const _defaultParams = SettlementParams();

SettlementResult _settle(
  List<SettlementMember> members, {
  Map<String, int>? authorSplit,
  SettlementParams params = _defaultParams,
}) {
  return _settlement.settle(
    SettlementInput(
      members: members,
      authorSplit: authorSplit,
      params: params,
    ),
  );
}

SettlementMember _member(
  String userId, {
  ClosureOutcome? outcome = ClosureOutcome.done,
  bool voter = true,
  Set<String>? support,
}) {
  return SettlementMember(
    userId: userId,
    outcome: outcome,
    voter: voter,
    support: support,
  );
}

List<SettlementMember> _threeDone({Set<String>? u1Support}) => [
      _member('u1', support: u1Support),
      _member('u2'),
      _member('u3'),
    ];

void _expectHelped(
  SettlementResult result,
  Map<String, double> expected, {
  double tol = _vectorTol,
}) {
  for (final entry in expected.entries) {
    expect(
      result.helped[entry.key],
      closeTo(entry.value, tol),
      reason: 'helped[${entry.key}]',
    );
  }
}

void _expectSilent(
  SettlementResult result,
  Map<String, double> expected, {
  double tol = _vectorTol,
}) {
  for (final entry in expected.entries) {
    expect(
      result.silent[entry.key],
      closeTo(entry.value, tol),
      reason: 'silent[${entry.key}]',
    );
  }
}

void _expectBands(
  SettlementResult result,
  Map<String, ClosureBand> expected,
) {
  for (final entry in expected.entries) {
    expect(result.band[entry.key], entry.value);
  }
}

void _requireA7aAcceptance(String scope) {
  expect(
    _a7aAcceptanceEnabled,
    isTrue,
    reason:
        'A7a $scope: enable _a7aAcceptanceEnabled after pinning Arch §5.5.2',
  );
}

void _assertA7aVector(
  SettlementResult result, {
  required String vectorId,
  required Map<String, double> silent,
  required Map<String, double> helped,
  required double lost,
  required Map<String, ClosureBand> bands,
}) {
  _expectSilent(result, silent);
  _expectHelped(result, helped);
  expect(result.lost, closeTo(lost, _vectorTol), reason: '$vectorId lost');
  _expectBands(result, bands);
}

void _assertA7aSelfScalingProperty(void Function() runCases) {
  _requireA7aAcceptance('self-scaling property');
  runCases();
}

void main() {
  group('EpisodeSettlement fixed vectors', () {
    test('V1 equal split, silence', () {
      final result = _settle(_threeDone());
      _expectHelped(result, {'u1': 0.2333, 'u2': 0.2333, 'u3': 0.2333});
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.asIfSilent,
        'u3': ClosureBand.asIfSilent,
      });
      expect(result.closeAck, {'u1', 'u2', 'u3'});
    });

    test('V2 split 70/20/10, silence', () {
      final result = _settle(
        _threeDone(),
        authorSplit: {'u1': 70, 'u2': 20, 'u3': 10},
      );
      _expectHelped(result, {
        'u1': 0.3856,
        'u2': 0.2074,
        'u3': 0.1069,
      });
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.asIfSilent,
        'u3': ClosureBand.asIfSilent,
      });
    });

    test('V3 split 70/20/10, u1 supports u3', () {
      final result = _settle(
        _threeDone(u1Support: {'u3'}),
        authorSplit: {'u1': 70, 'u2': 20, 'u3': 10},
      );
      _expectHelped(result, {
        'u1': 0.3856,
        'u2': 0.1471,
        'u3': 0.1672,
      });
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.lowered,
        'u3': ClosureBand.raised,
      });
    });

    test('V4 split 10/20/70, u1 supports u3', () {
      final result = _settle(
        _threeDone(u1Support: {'u3'}),
        authorSplit: {'u1': 10, 'u2': 20, 'u3': 70},
      );
      _expectHelped(result, {
        'u1': 0.1069,
        'u2': 0.1990,
        'u3': 0.3941,
      });
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.asIfSilent,
        'u3': ClosureBand.asIfSilent,
      });
    });

    test('V5 equal, u1 supports u2, u2 supports u1', () {
      final result = _settle([
        _member('u1', support: {'u2'}),
        _member('u2', support: {'u1'}),
        _member('u3'),
      ]);
      _expectHelped(result, {
        'u1': 0.2625,
        'u2': 0.2625,
        'u3': 0.1750,
      });
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.asIfSilent,
        'u3': ClosureBand.lowered,
      });
    });

    test('V6 u2 notDone, split u1 50 / u3 50, u1 and u3 support u2', () {
      final result = _settle(
        [
          _member('u1', support: {'u2'}),
          _member('u2', outcome: ClosureOutcome.notDone),
          _member('u3', support: {'u2'}),
        ],
        authorSplit: {'u1': 50, 'u3': 50},
      );
      _expectHelped(result, {
        'u1': 0.2771,
        'u2': 0.1458,
        'u3': 0.2771,
      });
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.lowered,
        'u2': ClosureBand.raised,
        'u3': ClosureBand.lowered,
      });
      expect(result.closeAck, {'u1', 'u3'});
    });

    test('V7 u2 cantJudge, u3 unanswered, split null', () {
      final result = _settle([
        _member('u1'),
        _member('u2', outcome: ClosureOutcome.cantJudge),
        _member('u3', outcome: null),
      ]);
      _expectHelped(result, {
        'u1': 0.2333,
        'u2': 0.2333,
        'u3': 0.2333,
      });
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.asIfSilent,
        'u3': ClosureBand.asIfSilent,
      });
      expect(result.closeAck, {'u1'});
    });

    test('V8 u2, u3 notDone, split null', () {
      final result = _settle([
        _member('u1'),
        _member('u2', outcome: ClosureOutcome.notDone),
        _member('u3', outcome: ClosureOutcome.notDone),
      ]);
      _expectHelped(result, {'u1': 0.4667, 'u2': 0, 'u3': 0});
      expect(result.lost, closeTo(0.2333, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.none,
        'u3': ClosureBand.none,
      });
    });

    test('V9 split 100/0/0, u1 supports u2', () {
      final result = _settle(
        _threeDone(u1Support: {'u2'}),
        authorSplit: {'u1': 100, 'u2': 0, 'u3': 0},
      );
      _expectHelped(result, {'u1': 0.4667, 'u2': 0.1167, 'u3': 0});
      expect(result.lost, closeTo(0.1167, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.raised,
        'u3': ClosureBand.none,
      });
    });

    test('V10 split 70/20/10, u1 supports u2 and u3 (all)', () {
      final v2 = _settle(
        _threeDone(),
        authorSplit: {'u1': 70, 'u2': 20, 'u3': 10},
      );
      final result = _settle(
        _threeDone(u1Support: {'u2', 'u3'}),
        authorSplit: {'u1': 70, 'u2': 20, 'u3': 10},
      );
      _expectHelped(result, v2.helped);
      expect(result.lost, closeTo(v2.lost, _vectorTol));
      _expectBands(result, v2.band);
    });

    test('V11 split 70/20/10, u3 is not a voter and supports u2', () {
      final v2 = _settle(
        _threeDone(),
        authorSplit: {'u1': 70, 'u2': 20, 'u3': 10},
      );
      final result = _settle(
        [
          _member('u1'),
          _member('u2'),
          _member('u3', voter: false, support: {'u2'}),
        ],
        authorSplit: {'u1': 70, 'u2': 20, 'u3': 10},
      );
      _expectHelped(result, v2.helped);
      expect(result.lost, closeTo(v2.lost, _vectorTol));
      _expectBands(result, v2.band);
    });

    test('V12 n = 2, split 80/20, u1 supports u2', () {
      final result = _settle(
        [
          _member('u1', support: {'u2'}),
          _member('u2'),
        ],
        authorSplit: {'u1': 80, 'u2': 20},
      );
      _expectHelped(result, {'u1': 0.5600, 'u2': 0.1400});
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.none,
        'u2': ClosureBand.none,
      });
    });

    test('V13 n = 1, done', () {
      final result = _settle([_member('u1')]);
      _expectHelped(result, {'u1': 0.7000});
      expect(result.lost, closeTo(0, _vectorTol));
      expect(result.band['u1'], ClosureBand.none);
    });

    test('V14 n = 3, all notDone', () {
      final result = _settle([
        _member('u1', outcome: ClosureOutcome.notDone),
        _member('u2', outcome: ClosureOutcome.notDone),
        _member('u3', outcome: ClosureOutcome.notDone),
      ]);
      _expectHelped(result, {'u1': 0, 'u2': 0, 'u3': 0});
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.none,
        'u2': ClosureBand.none,
        'u3': ClosureBand.none,
      });
      expect(result.closeAck, isEmpty);
    });

    test('V15 n = 4, split 40/30/20/10, u1 supports u4', () {
      final result = _settle(
        [
          _member('u1', support: {'u4'}),
          _member('u2'),
          _member('u3'),
          _member('u4'),
        ],
        authorSplit: {'u1': 40, 'u2': 30, 'u3': 20, 'u4': 10},
      );
      _expectHelped(result, {
        'u1': 0.2616,
        'u2': 0.1834,
        'u3': 0.1301,
        'u4': 0.1249,
      });
      expect(result.lost, closeTo(0, _vectorTol));
      _expectBands(result, {
        'u1': ClosureBand.asIfSilent,
        'u2': ClosureBand.asIfSilent,
        'u3': ClosureBand.asIfSilent,
        'u4': ClosureBand.raised,
      });
    });
  });

  group('support self-scaling (A7a)', () {
    test('V16 u3 notDone, split 30/70, u1 supports u3', () {
      _requireA7aAcceptance('V16');
      final result = _settle(
        [
          _member('u1', support: {'u3'}),
          _member('u2'),
          _member('u3', outcome: ClosureOutcome.notDone),
        ],
        authorSplit: {'u1': 30, 'u2': 70},
      );
      _assertA7aVector(
        result,
        vectorId: 'V16',
        silent: {'u1': 0.3033, 'u2': 0.3967, 'u3': 0},
        helped: {'u1': 0.3033, 'u2': 0.3412, 'u3': 0.0554},
        lost: 0,
        bands: {
          'u1': ClosureBand.asIfSilent,
          'u2': ClosureBand.asIfSilent,
          'u3': ClosureBand.raised,
        },
      );
    });

    test('V17 all done, split 30/50/20, u1 supports u3', () {
      _requireA7aAcceptance('V17');
      final result = _settle(
        _threeDone(u1Support: {'u3'}),
        authorSplit: {'u1': 30, 'u2': 50, 'u3': 20},
      );
      _assertA7aVector(
        result,
        vectorId: 'V17',
        silent: {'u1': 0.2275, 'u2': 0.3125, 'u3': 0.1600},
        helped: {'u1': 0.2275, 'u2': 0.2729, 'u3': 0.1996},
        lost: 0,
        bands: {
          'u1': ClosureBand.asIfSilent,
          'u2': ClosureBand.asIfSilent,
          'u3': ClosureBand.raised,
        },
      );
    });

    test('V18 all done, split 30/35/35, u1 supports u3', () {
      _requireA7aAcceptance('V18');
      final result = _settle(
        _threeDone(u1Support: {'u3'}),
        authorSplit: {'u1': 30, 'u2': 35, 'u3': 35},
      );
      _assertA7aVector(
        result,
        vectorId: 'V18',
        silent: {'u1': 0.2154, 'u2': 0.2423, 'u3': 0.2423},
        helped: {'u1': 0.2154, 'u2': 0.2146, 'u3': 0.2700},
        lost: 0,
        bands: {
          'u1': ClosureBand.asIfSilent,
          'u2': ClosureBand.asIfSilent,
          'u3': ClosureBand.asIfSilent,
        },
      );
    });

    test('V19 all done, split 30/10/60, u1 supports u3', () {
      _requireA7aAcceptance('V19');
      final result = _settle(
        _threeDone(u1Support: {'u3'}),
        authorSplit: {'u1': 30, 'u2': 10, 'u3': 60},
      );
      _assertA7aVector(
        result,
        vectorId: 'V19',
        silent: {'u1': 0.2528, 'u2': 0.0917, 'u3': 0.3556},
        helped: {'u1': 0.2528, 'u2': 0.0838, 'u3': 0.3635},
        lost: 0,
        bands: {
          'u1': ClosureBand.asIfSilent,
          'u2': ClosureBand.asIfSilent,
          'u3': ClosureBand.asIfSilent,
        },
      );
    });

    test('V20 u2 notDone, split 30/70 u1/u3, u1 supports u3', () {
      _requireA7aAcceptance('V20');
      final result = _settle(
        [
          _member('u1', support: {'u3'}),
          _member('u2', outcome: ClosureOutcome.notDone),
          _member('u3'),
        ],
        authorSplit: {'u1': 30, 'u3': 70},
      );
      _assertA7aVector(
        result,
        vectorId: 'V20',
        silent: {'u1': 0.3033, 'u2': 0, 'u3': 0.3967},
        helped: {'u1': 0.3033, 'u2': 0, 'u3': 0.3967},
        lost: 0,
        bands: {
          'u1': ClosureBand.asIfSilent,
          'u2': ClosureBand.none,
          'u3': ClosureBand.asIfSilent,
        },
      );
    });

    test('supported gain shrinks as author share grows; unsupported loss scales', () {
      _assertA7aSelfScalingProperty(() {
        final rng = Random(7);
        var casesRun = 0;
        while (casesRun < 500) {
        final a1 = 5 + 5 * rng.nextInt(18);
        final maxA3 = 100 - a1 - 5;
        if (maxA3 < 10) {
          continue;
        }
        final a3Choices = <int>[
          for (var a3 = 5; a3 <= maxA3; a3 += 5) a3,
        ];
        if (a3Choices.length < 2) {
          continue;
        }
        final iLow = rng.nextInt(a3Choices.length - 1);
        final iHigh =
            iLow + 1 + rng.nextInt(a3Choices.length - 1 - iLow);
        final a3Low = a3Choices[iLow];
        final a3High = a3Choices[iHigh];
        final a2Low = 100 - a1 - a3Low;
        final a2High = 100 - a1 - a3High;
        if (a2Low < 5 || a2High < 5) {
          continue;
        }

          final splitLow = {'u1': a1, 'u2': a2Low, 'u3': a3Low};
          final splitHigh = {'u1': a1, 'u2': a2High, 'u3': a3High};
          casesRun++;

          final silentMembers = _threeDone();
          final supportMembers = _threeDone(u1Support: {'u3'});

          final silentLow = _settle(silentMembers, authorSplit: splitLow);
          final helpedLow = _settle(supportMembers, authorSplit: splitLow);
          final silentHigh = _settle(silentMembers, authorSplit: splitHigh);
          final helpedHigh = _settle(supportMembers, authorSplit: splitHigh);

          final gainLow =
              helpedLow.helped['u3']! - silentLow.silent['u3']!;
          final gainHigh =
              helpedHigh.helped['u3']! - silentHigh.silent['u3']!;
          expect(
            gainLow,
            greaterThanOrEqualTo(gainHigh - _impartialityTol),
            reason:
                'case $casesRun a1=$a1 a3Low=$a3Low a3High=$a3High gain u3',
          );

          final lossLow =
              silentLow.silent['u2']! - helpedLow.helped['u2']!;
          final lossHigh =
              silentHigh.silent['u2']! - helpedHigh.helped['u2']!;
          expect(
            lossLow,
            greaterThanOrEqualTo(-_impartialityTol),
            reason: 'case $casesRun a2Low=$a2Low loss u2 non-negative',
          );
          expect(
            lossHigh,
            greaterThanOrEqualTo(-_impartialityTol),
            reason: 'case $casesRun a2High=$a2High loss u2 non-negative',
          );
          expect(
            lossLow,
            greaterThanOrEqualTo(lossHigh - _impartialityTol),
            reason:
                'case $casesRun a2Low=$a2Low a2High=$a2High loss u2 non-decreasing in a2',
          );
        }
        expect(casesRun, 500);
      });
    });
  });

  group('EpisodeSettlement properties', () {
    final rng = Random(42);

    List<SettlementMember> _randomMembers(int n) {
      final ids = List.generate(n, (i) => 'm${i.toString().padLeft(2, '0')}');
      return ids.map((id) {
        final outcomeRoll = rng.nextInt(4);
        final ClosureOutcome? outcome = switch (outcomeRoll) {
          0 => ClosureOutcome.done,
          1 => ClosureOutcome.notDone,
          2 => ClosureOutcome.cantJudge,
          _ => null,
        };
        final voter = rng.nextBool();
        Set<String>? support;
        if (rng.nextBool()) {
          final others = ids.where((o) => o != id).toList();
          final count = rng.nextInt(others.length + 1);
          if (count > 0) {
            others.shuffle(rng);
            support = others.take(count).toSet();
          }
        }
        return SettlementMember(
          userId: id,
          outcome: outcome,
          voter: voter,
          support: support,
        );
      }).toList();
    }

    Map<String, int>? _randomAuthorSplit(List<SettlementMember> members) {
      if (rng.nextBool()) {
        return null;
      }
      final aIds = members
          .where((m) => m.outcome != ClosureOutcome.notDone)
          .map((m) => m.userId)
          .toList();
      if (aIds.isEmpty) {
        return null;
      }
      var remaining = 100;
      final split = <String, int>{};
      for (var i = 0; i < aIds.length; i++) {
        if (i == aIds.length - 1) {
          split[aIds[i]] = remaining;
        } else {
          final maxChunk = remaining - 5 * (aIds.length - i - 1);
          final chunk = 5 * rng.nextInt(maxChunk ~/ 5 + 1);
          split[aIds[i]] = chunk;
          remaining -= chunk;
        }
      }
      return split;
    }

    test('impartiality: own helped unchanged when only own support changes', () {
      for (var case_ = 0; case_ < 2000; case_++) {
        final n = 1 + rng.nextInt(8);
        final members = _randomMembers(n);
        final split = _randomAuthorSplit(members);
        final base = _settle(members, authorSplit: split);

        for (var i = 0; i < members.length; i++) {
          final altSupport = rng.nextBool()
              ? null
              : members
                  .map((m) => m.userId)
                  .where((id) => id != members[i].userId)
                  .take(rng.nextInt(n))
                  .toSet();
          final tweaked = [
            for (var j = 0; j < members.length; j++)
              if (j == i)
                SettlementMember(
                  userId: members[j].userId,
                  outcome: members[j].outcome,
                  voter: members[j].voter,
                  support: altSupport,
                )
              else
                members[j],
          ];
          final alt = _settle(tweaked, authorSplit: split);
          expect(
            alt.helped[members[i].userId],
            closeTo(base.helped[members[i].userId]!, _impartialityTol),
            reason: 'case $case_ member ${members[i].userId}',
          );
        }
      }
    });

    test('monotonicity: isolated voter support vs silence', () {
      for (var case_ = 0; case_ < 2000; case_++) {
        final n = 1 + rng.nextInt(8);
        final members = _randomMembers(n);
        final split = _randomAuthorSplit(members);
        final silentMembers = members
            .map(
              (m) => SettlementMember(
                userId: m.userId,
                outcome: m.outcome,
                voter: m.voter,
                support: null,
              ),
            )
            .toList();
        final silent = _settle(silentMembers, authorSplit: split);

        for (var i = 0; i < members.length; i++) {
          final m = members[i];
          if (!m.voter || m.support == null || m.support!.isEmpty) {
            continue;
          }
          final others = members.map((x) => x.userId).where((id) => id != m.userId).toSet();
          if (m.support!.length >= others.length) {
            continue;
          }
          final onlyI = members
              .map(
                (x) => SettlementMember(
                  userId: x.userId,
                  outcome: x.outcome,
                  voter: x.voter,
                  support: x.userId == m.userId ? m.support : null,
                ),
              )
              .toList();
          final withSupport = _settle(onlyI, authorSplit: split);
          for (final j in m.support!) {
            expect(
              withSupport.helped[j]! - silent.helped[j]!,
              greaterThanOrEqualTo(-_impartialityTol),
              reason: 'case $case_ voter ${m.userId} supported $j',
            );
          }
          for (final k in others.where((id) => !m.support!.contains(id))) {
            expect(
              withSupport.helped[k]! - silent.helped[k]!,
              lessThanOrEqualTo(_impartialityTol),
              reason: 'case $case_ voter ${m.userId} unsupported $k',
            );
          }
        }
      }
    });

    test('conservation', () {
      for (var case_ = 0; case_ < 2000; case_++) {
        final n = 1 + rng.nextInt(8);
        final members = _randomMembers(n);
        final split = _randomAuthorSplit(members);
        final result = _settle(members, authorSplit: split);
        final aNonEmpty = members.any((m) => m.outcome != ClosureOutcome.notDone);
        if (aNonEmpty) {
          final sum =
              result.helped.values.fold<double>(0, (a, b) => a + b) + result.lost;
          expect(sum, closeTo(_poolH, _conservationTol), reason: 'case $case_');
        } else {
          expect(result.helped.values.every((h) => h == 0), isTrue);
          expect(result.lost, closeTo(0, _conservationTol));
        }
      }
    });

    test('permutation invariance', () {
      for (var case_ = 0; case_ < 2000; case_++) {
        final n = 1 + rng.nextInt(8);
        final members = _randomMembers(n);
        final split = _randomAuthorSplit(members);
        final canonical = _settle(members, authorSplit: split);
        final shuffled = List<SettlementMember>.from(members);
        shuffled.shuffle(rng);
        final permuted = _settle(shuffled, authorSplit: split);
        expect(permuted.helped, canonical.helped);
        expect(permuted.silent, canonical.silent);
        expect(permuted.band, canonical.band);
        expect(permuted.lost, closeTo(canonical.lost, _conservationTol));
        expect(permuted.closeAck, canonical.closeAck);
      }
    });

    test('all-supported equivalent to silence', () {
      for (var case_ = 0; case_ < 2000; case_++) {
        final n = 3 + rng.nextInt(6);
        final members = _randomMembers(n);
        final split = _randomAuthorSplit(members);
        final silentMembers = members
            .map(
              (m) => SettlementMember(
                userId: m.userId,
                outcome: m.outcome,
                voter: m.voter,
                support: null,
              ),
            )
            .toList();
        final silent = _settle(silentMembers, authorSplit: split);

        final allSupported = members.map((m) {
          if (!m.voter) {
            return m;
          }
          final others =
              members.map((x) => x.userId).where((id) => id != m.userId).toSet();
          return SettlementMember(
            userId: m.userId,
            outcome: m.outcome,
            voter: m.voter,
            support: others,
          );
        }).toList();
        final covered = _settle(allSupported, authorSplit: split);
        expect(covered.helped, silent.helped);
        expect(covered.lost, closeTo(silent.lost, _conservationTol));
      }
    });

    test('notDone members get no author part when all supports null', () {
      for (var case_ = 0; case_ < 2000; case_++) {
        final n = 1 + rng.nextInt(8);
        final members = _randomMembers(n);
        final split = _randomAuthorSplit(members);
        final noSupport = members
            .map(
              (m) => SettlementMember(
                userId: m.userId,
                outcome: m.outcome,
                voter: m.voter,
                support: null,
              ),
            )
            .toList();
        final result = _settle(noSupport, authorSplit: split);
        for (final m in members) {
          if (m.outcome == ClosureOutcome.notDone) {
            expect(
              result.helped[m.userId],
              closeTo(0, _impartialityTol),
              reason: 'case notDone ${m.userId}',
            );
          }
        }
      }
    });
  });
}
