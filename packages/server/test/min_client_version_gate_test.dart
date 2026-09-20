import 'dart:convert';
import 'dart:io';

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

    /// U19 — the other half of the one-release cutover.
    ///
    /// D19 ships the floor and the client that satisfies it in the *same*
    /// release. A floor above the shipped client version is not a stricter
    /// gate, it is a server that rejects every client there is. Nothing
    /// asserted this before U19: the floor had its own test, the client
    /// version had none, and the two could disagree silently.
    test('the shipped client version satisfies the floor', () {
      expect(
        _compare(_shippedClientVersion(), kDefaultMinClientVersion),
        greaterThanOrEqualTo(0),
        reason:
            'packages/client/pubspec.yaml is ${_shippedClientVersion()} but '
            'the server floor is $kDefaultMinClientVersion — the server '
            'would reject every client.',
      );
    });

    /// The cache-buster and the manifest carry the version into the browser.
    /// A `?v=` that disagrees with the pubspec serves a returning client a
    /// stale bundle — of a build the floor then rejects, with no way for that
    /// client to fetch the one that would be accepted.
    ///
    /// `web/manifest.json` carries a `skip-worktree` bit in some worktrees
    /// (the build hook rewrites it, so local builds would otherwise dirty the
    /// tree). That bit hid a tracked value stuck at `7.3.1` across a dozen
    /// releases. This test reads the working copy, so it is green locally and
    /// red on a fresh checkout until the tracked value is committed — which
    /// is the drift it exists to surface.
    test('every checked-in copy of the client version agrees', () {
      final pubspec = _shippedClientVersion();
      expect(_bootstrapCacheBusterVersion(), pubspec);
      expect(_manifestVersion(), pubspec);
    });

    test('is the next minor, not a jump that skips a real release', () {
      // The floor names a version U19 must actually ship. Anything further
      // ahead locks out the release that carries the contract as well.
      expect(kDefaultMinClientVersion, '7.19.0');
    });
  });
}

/// Path to a file in the sibling client package. Server tests run with
/// `packages/server` as the working directory.
File _clientFile(String relative) => File('../client/$relative');

String _shippedClientVersion() {
  final line = _clientFile('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.split(':')[1].trim();
}

String _bootstrapCacheBusterVersion() {
  final html = _clientFile('web/index.html').readAsStringSync();
  final match = RegExp(
    r'flutter_bootstrap\.js\?v=([0-9]+\.[0-9]+\.[0-9]+)',
  ).firstMatch(html);
  if (match == null) {
    fail('web/index.html has no flutter_bootstrap.js?v= cache-buster');
  }
  return match.group(1)!;
}

String _manifestVersion() =>
    (jsonDecode(_clientFile('web/manifest.json').readAsStringSync())
        as Map<String, dynamic>)['version'] as String;
