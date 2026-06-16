import 'package:tentura_server/domain/evaluation/beacon_evaluation_value.dart';

import 'trust_bin.dart';

TrustBin? reviewValueToBin(int value) => switch (value) {
  BeaconEvaluationValue.neg2 => TrustBin.veryBad,
  BeaconEvaluationValue.neg1 => TrustBin.bad,
  BeaconEvaluationValue.zero => TrustBin.noEffect,
  BeaconEvaluationValue.pos1 => TrustBin.good,
  BeaconEvaluationValue.pos2 => TrustBin.veryGood,
  _ => null,
};

TrustBin? voteAmountToBin(int amount) => switch (amount) {
  1 => TrustBin.good,
  -1 => TrustBin.bad,
  0 => TrustBin.noEffect,
  _ => null,
};
