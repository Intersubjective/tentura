import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

/// The last client version built **before** the request-centric attention
/// contract landed. The client-side work of this plan (U15R-*, U16*, U17*)
/// all shipped under `packages/client/pubspec.yaml` version `7.18.0` without
/// a floor bump, so `7.18.0` is a version a pre-cutover build can carry and
/// the floor must exclude it.
const _lastPreCutoverClientVersion = '7.18.0';

List<int> _parse(String version) => [
  for (final part in version.split('.')) int.parse(part),
];

/// Compares `a` to `b` the way the announced floor is read: three numeric
/// components, most significant first.
int _compare(String a, String b) {
  final left = _parse(a);
  final right = _parse(b);
  for (var i = 0; i < left.length; i++) {
    final c = left[i].compareTo(right[i]);
    if (c != 0) return c;
  }
  return 0;
}

void main() {
  group('U18c — the cutover floor', () {
    test('_compare orders the components it claims to order', () {
      expect(_compare('7.18.0', '7.18.0'), 0);
      expect(_compare('7.19.0', '7.18.0'), greaterThan(0));
      expect(_compare('7.9.0', '7.18.0'), lessThan(0));
      expect(_compare('8.0.0', '7.18.0'), greaterThan(0));
    });

    test('excludes every client built before the attention contract', () {
      // D19 is a coordinated cutover with no dual-behaviour window: a client
      // that predates this plan's client-side contract must not be able to
      // talk to the new server at all. `7.18.0` is the highest version such a
      // build carries, so a floor equal to it would admit them.
      expect(
        _compare(kDefaultMinClientVersion, _lastPreCutoverClientVersion),
        greaterThan(0),
        reason:
            'kDefaultMinClientVersion must be strictly above '
            '$_lastPreCutoverClientVersion; U19 ships the matching client '
            'version in packages/client/pubspec.yaml.',
      );
    });

    test('is the next minor, not a jump that skips a real release', () {
      // The floor names a version U19 must actually ship. Anything further
      // ahead locks out the release that carries the contract as well.
      expect(kDefaultMinClientVersion, '7.19.0');
    });
  });
}
