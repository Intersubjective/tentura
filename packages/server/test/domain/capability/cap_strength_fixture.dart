import 'dart:math' as math;

import 'package:tentura_server/domain/capability/capability_consts.dart';

/// Test-only mirror of SQL `cap_strength` with `anchor = now()`.
double capStrengthAtNow({
  required double rawSum,
  required double k,
}) {
  if (rawSum <= 0) {
    return 0;
  }
  return rawSum / (k + rawSum);
}

/// Decay factor for one ledger row observed [daysAgo] days before rebuild.
double capDecayFactor({
  required int daysAgo,
  required int halfLifeSeconds,
}) {
  if (daysAgo < 0) {
    throw ArgumentError.value(daysAgo, 'daysAgo', 'must be non-negative');
  }
  final ageSeconds = daysAgo * 86400;
  return math.pow(2, -ageSeconds / halfLifeSeconds).toDouble();
}

bool isWithinEvidenceWindow(int daysAgo) {
  // Matches eligibility: created_at + make_interval(months => 24) > now()
  // Approximate with 30-day months — conservative for border tests.
  return daysAgo < kCapWindowMonths * 30;
}

double effectiveOutcomeStrength({
  required int daysAgo,
  int observationCount = 1,
}) {
  if (!isWithinEvidenceWindow(daysAgo)) {
    return 0;
  }
  final raw = observationCount *
      capDecayFactor(
        daysAgo: daysAgo,
        halfLifeSeconds: kCapHalfLifeOutSeconds,
      );
  return capStrengthAtNow(rawSum: raw, k: kCapKOut);
}

double effectiveSeedStrength({
  required int daysAgo,
  int observationCount = 1,
}) {
  if (!isWithinEvidenceWindow(daysAgo)) {
    return 0;
  }
  final raw = observationCount *
      capDecayFactor(
        daysAgo: daysAgo,
        halfLifeSeconds: kCapHalfLifeSeedSeconds,
      );
  return capStrengthAtNow(rawSum: raw, k: kCapKSeed);
}
