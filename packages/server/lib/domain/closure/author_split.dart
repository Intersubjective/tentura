import 'dart:convert';

import 'package:crypto/crypto.dart';

int minPct(int sizeOfA) {
  if (sizeOfA > 20) {
    throw ArgumentError('sizeOfA must be at most 20');
  }
  if (sizeOfA <= 1) {
    return 0;
  }
  return 5;
}

String _tieBreakKey(String beaconId, String helperId) {
  return sha256.convert(utf8.encode('$beaconId:$helperId')).toString();
}

Map<String, int> apportion({
  required int total,
  required Map<String, num> weights,
  required int min,
  required String beaconId,
}) {
  if (weights.isEmpty) {
    return {};
  }

  final w = Map<String, num>.from(weights);
  if (w.values.every((v) => v == 0)) {
    for (final k in w.keys) {
      w[k] = 1;
    }
  }

  final targets = <String, double>{};
  final fixed = <String>{};

  while (true) {
    final unfixed = w.keys.where((k) => !fixed.contains(k)).toList();
    if (unfixed.isEmpty) {
      break;
    }
    final rem = total - min * fixed.length;
    final sumW = unfixed.fold<num>(0, (s, k) => s + w[k]!);
    var newlyFixed = false;
    for (final k in unfixed) {
      final target = rem * w[k]! / sumW;
      if (target < min) {
        fixed.add(k);
        targets[k] = min.toDouble();
        newlyFixed = true;
      }
    }
    if (!newlyFixed) {
      for (final k in unfixed) {
        targets[k] = rem * w[k]! / sumW;
      }
      break;
    }
  }

  final units = <String, int>{};
  for (final k in w.keys) {
    final target = targets[k]!;
    units[k] = (target / 5 + 1e-9).floor();
  }

  final r = total ~/ 5 - units.values.fold<int>(0, (s, u) => s + u);
  if (r > 0) {
    final ranked = w.keys.toList()
      ..sort((a, b) {
        final fracA = targets[a]! / 5 - units[a]!;
        final fracB = targets[b]! / 5 - units[b]!;
        final cmp = fracB.compareTo(fracA);
        if (cmp != 0) {
          return cmp;
        }
        return _tieBreakKey(beaconId, a).compareTo(_tieBreakKey(beaconId, b));
      });
    for (var i = 0; i < r && i < ranked.length; i++) {
      units[ranked[i]] = units[ranked[i]]! + 1;
    }
  }

  return {for (final e in units.entries) e.key: e.value * 5};
}

Map<String, int> moveSlider({
  required Map<String, int> current,
  required String helperId,
  required int value,
  required String beaconId,
}) {
  final size = current.length;
  final min = minPct(size);
  final maxValue = 100 - min * (size - 1);
  var clamped = value;
  if (clamped < min) {
    clamped = min;
  } else if (clamped > maxValue) {
    clamped = maxValue;
  }
  final moved = ((clamped / 5).round()) * 5;

  final others = Map<String, num>.fromEntries(
    current.entries.where((e) => e.key != helperId).map(
          (e) => MapEntry(e.key, e.value),
        ),
  );

  final rest = apportion(
    total: 100 - moved,
    weights: others,
    min: min,
    beaconId: beaconId,
  );

  return {helperId: moved, ...rest};
}

Map<String, int>? renormalize({
  required Map<String, int>? current,
  required Set<String> newA,
  required String beaconId,
}) {
  if (current == null || newA.isEmpty || newA.length > 20) {
    return null;
  }
  if (newA.length == 1) {
    return {newA.first: 100};
  }

  final newcomerWeight = 100 / newA.length;
  final weights = <String, num>{
    for (final id in newA)
      id: current.containsKey(id) ? current[id]! : newcomerWeight,
  };

  return apportion(
    total: 100,
    weights: weights,
    min: minPct(newA.length),
    beaconId: beaconId,
  );
}

String? validate(Map<String, int> split, Set<String> a) {
  if (a.length > 20) {
    return 'splitTooLarge';
  }
  if (a.isEmpty) {
    return 'emptyA';
  }
  if (split.keys.toSet().difference(a).isNotEmpty ||
      a.difference(split.keys.toSet()).isNotEmpty) {
    return 'keysMismatch';
  }
  var sum = 0;
  final min = minPct(a.length);
  for (final v in split.values) {
    if (v < 0 || v > 100 || v % 5 != 0) {
      return 'invalidValue';
    }
    if (v < min) {
      return 'belowMin';
    }
    sum += v;
  }
  if (sum != 100) {
    return 'sumNot100';
  }
  return null;
}
