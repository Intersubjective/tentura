import 'closure_band.dart';
import 'closure_outcome.dart';
import 'settlement_params.dart';

final class SettlementMember {
  const SettlementMember({
    required this.userId,
    this.outcome,
    this.voter = true,
    this.support,
  });

  final String userId;
  final ClosureOutcome? outcome;
  final bool voter;
  final Set<String>? support;
}

final class SettlementInput {
  const SettlementInput({
    required this.members,
    this.authorSplit,
    required this.params,
  });

  final List<SettlementMember> members;
  final Map<String, int>? authorSplit;
  final SettlementParams params;
}

final class SettlementResult {
  const SettlementResult({
    required this.helped,
    required this.silent,
    required this.band,
    required this.lost,
    required this.closeAck,
  });

  final Map<String, double> helped;
  final Map<String, double> silent;
  final Map<String, ClosureBand> band;
  final double lost;
  final Set<String> closeAck;
}

class EpisodeSettlement {
  SettlementResult settle(SettlementInput input) {
    final sorted = List<SettlementMember>.from(input.members)
      ..sort((a, b) => a.userId.compareTo(b.userId));
    final params = input.params;
    final poolH = (1 - params.rho) * params.B;

    final effectiveOutcome = <String, ClosureOutcome>{};
    for (final m in sorted) {
      effectiveOutcome[m.userId] = switch (m.outcome) {
        null => ClosureOutcome.cantJudge,
        ClosureOutcome.notDone => ClosureOutcome.notDone,
        ClosureOutcome.done => ClosureOutcome.done,
        ClosureOutcome.cantJudge => ClosureOutcome.cantJudge,
      };
    }

    final closeAck = sorted
        .where((m) => m.outcome == ClosureOutcome.done)
        .map((m) => m.userId)
        .toSet();

    final aSet = sorted
        .where((m) => effectiveOutcome[m.userId] != ClosureOutcome.notDone)
        .map((m) => m.userId)
        .toList();

    final aPct = _authorPercentages(sorted, aSet, input.authorSplit);

    if (aSet.isEmpty) {
      final zeros = {for (final m in sorted) m.userId: 0.0};
      return SettlementResult(
        helped: zeros,
        silent: Map<String, double>.from(zeros),
        band: {for (final m in sorted) m.userId: ClosureBand.none},
        lost: 0,
        closeAck: closeAck,
      );
    }

    final n = sorted.length;
    final alpha = n >= 3 ? params.alphaA : 1.0;

    final withSupport = _runPeerLoop(
      sorted,
      aPct,
      params,
      poolH,
      alpha,
      ignoreSupport: false,
    );
    final silentRun = _runPeerLoop(
      sorted,
      aPct,
      params,
      poolH,
      alpha,
      ignoreSupport: true,
    );

    final helped = <String, double>{};
    final silent = <String, double>{};
    for (final m in sorted) {
      final id = m.userId;
      helped[id] = withSupport.authorPart[id]! + withSupport.imp[id]!;
      silent[id] = silentRun.authorPart[id]! + silentRun.imp[id]!;
    }

    final band = <String, ClosureBand>{};
    for (final m in sorted) {
      band[m.userId] = _bandOf(
        n: n,
        helped: helped[m.userId]!,
        silentVal: silent[m.userId]!,
        bandThreshold: params.bandThreshold,
      );
    }

    return SettlementResult(
      helped: helped,
      silent: silent,
      band: band,
      lost: withSupport.lost,
      closeAck: closeAck,
    );
  }

  Map<String, double> _authorPercentages(
    List<SettlementMember> sorted,
    List<String> aSet,
    Map<String, int>? authorSplit,
  ) {
    final aPct = <String, double>{for (final m in sorted) m.userId: 0};
    if (authorSplit == null) {
      final share = 100.0 / aSet.length;
      for (final id in aSet) {
        aPct[id] = share;
      }
    } else {
      for (final id in aSet) {
        aPct[id] = (authorSplit[id] ?? 0).toDouble();
      }
    }
    return aPct;
  }

  ClosureBand _bandOf({
    required int n,
    required double helped,
    required double silentVal,
    required double bandThreshold,
  }) {
    if (n <= 2 || (helped == 0 && silentVal == 0)) {
      return ClosureBand.none;
    }
    if (silentVal == 0 && helped > 0) {
      return ClosureBand.raised;
    }
    if (helped > (1 + bandThreshold) * silentVal) {
      return ClosureBand.raised;
    }
    if (helped < (1 - bandThreshold) * silentVal) {
      return ClosureBand.lowered;
    }
    return ClosureBand.asIfSilent;
  }

  ({Map<String, double> authorPart, Map<String, double> imp, double lost})
      _runPeerLoop(
    List<SettlementMember> sorted,
    Map<String, double> aPct,
    SettlementParams params,
    double poolH,
    double alpha, {
    required bool ignoreSupport,
  }) {
    final n = sorted.length;
    final authorPart = <String, double>{};
    final imp = <String, double>{for (final m in sorted) m.userId: 0};
    var lost = 0.0;

    for (final m in sorted) {
      authorPart[m.userId] = alpha * poolH * aPct[m.userId]! / 100;
    }

    for (final voter in sorted) {
      final i = voter.userId;
      final slice = (1 - alpha) *
          poolH *
          (params.beta / n + (1 - params.beta) * aPct[i]! / 100);

      final others = sorted.where((m) => m.userId != i).toList();
      final otherIds = others.map((m) => m.userId).toSet();

      var s = 0.0;
      for (final o in others) {
        s += aPct[o.userId]!;
      }

      Set<String> u = {};
      if (!ignoreSupport &&
          voter.voter &&
          n >= 3 &&
          voter.support != null &&
          voter.support!.isNotEmpty) {
        u = voter.support!.intersection(otherIds);
        if (u.length == otherIds.length) {
          u = {};
        }
      }

      if (s == 0) {
        if (u.isNotEmpty) {
          final share = slice * params.t / u.length;
          for (final j in u) {
            imp[j] = imp[j]! + share;
          }
          lost += slice * (1 - params.t);
        } else {
          lost += slice;
        }
        continue;
      }

      final base = <String, double>{};
      for (final o in others) {
        base[o.userId] = aPct[o.userId]! / s;
      }

      final dir = <String, double>{};
      if (u.isEmpty) {
        dir.addAll(base);
      } else {
        final nSet = otherIds.difference(u);
        var take = 0.0;
        for (final k in nSet) {
          take += params.t * base[k]!;
        }
        for (final k in nSet) {
          dir[k] = (1 - params.t) * base[k]!;
        }
        final uShare = take / u.length;
        for (final j in u) {
          dir[j] = base[j]! + uShare;
        }
      }

      for (final o in others) {
        imp[o.userId] = imp[o.userId]! + slice * dir[o.userId]!;
      }
    }

    return (authorPart: authorPart, imp: imp, lost: lost);
  }
}
