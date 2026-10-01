import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A23: the old review ("evaluation") feature is removed from the client.
///
/// Mirrors the unit's acceptance grep:
/// `grep -rln "evaluation\|reviewWindow\|review_window" lib test integration_test
///  --include=*.dart | grep -v "\.g\.dart\|\.gql\.dart"`.
final _removedPattern = RegExp('evaluation|reviewWindow|review_window');

/// Identifiers allowed to survive. `BeaconStatus.reviewOpen` does not match
/// [_removedPattern] today; the list exists so a future allowlisted identifier
/// that does match is stripped before the scan.
const _allowedIdentifiers = <String>['BeaconStatus.reviewOpen'];

Iterable<File> _dartFiles(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where(
        (f) => !f.path.endsWith('.g.dart') && !f.path.endsWith('.gql.dart'),
      );
}

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Set<String> _l10nMembers(String source) => RegExp(
  r'^  String (?:get )?(\w+)',
  multiLine: true,
).allMatches(source).map((m) => m.group(1)!).toSet();

/// Hand-written `lib` code that survives the removal: no generated files, no
/// code under the removed feature, and no comments (a doc mention is not use).
String _liveLibSource() => [
  for (final f in _dartFiles('lib'))
    if (!f.path.startsWith('lib/ui/l10n/') &&
        !f.path.startsWith('lib/features/evaluation/') &&
        !RegExp(r'\.(freezed|gr|config)\.dart$|/_g/').hasMatch(f.path))
      f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n'),
].join('\n');

void main() {
  test('lib/features/evaluation is deleted', () {
    expect(Directory('lib/features/evaluation').existsSync(), isFalse);
  });

  test('test/features/evaluation is deleted with the feature', () {
    expect(Directory('test/features/evaluation').existsSync(), isFalse);
  });

  test(
    'no evaluation / reviewWindow / review_window left in client sources',
    () {
      final offenders = <String>[];
      for (final root in const ['lib', 'test', 'integration_test']) {
        for (final file in _dartFiles(root)) {
          // This guard names the removed identifiers itself.
          if (file.path.endsWith('evaluation_feature_removal_test.dart')) {
            continue;
          }
          var source = file.readAsStringSync();
          for (final allowed in _allowedIdentifiers) {
            source = source.replaceAll(allowed, '');
          }
          if (_removedPattern.hasMatch(source)) offenders.add(file.path);
        }
      }
      expect(offenders..sort(), isEmpty);
    },
  );

  test('review routes and path constants are removed everywhere', () {
    final offenders = <String>[];
    for (final root in const ['lib', 'test', 'integration_test']) {
      for (final file in _dartFiles(root)) {
        if (file.path.endsWith('evaluation_feature_removal_test.dart')) {
          continue;
        }
        final source = file.readAsStringSync();
        if (RegExp(
          r'/beacon/reviews?(?![A-Za-z])|kPathReviewContributions|kPathReceivedReviews',
        ).hasMatch(source)) {
          offenders.add(file.path);
        }
      }
    }
    expect(offenders..sort(), isEmpty);

    final router = File('lib/app/router/root_router.dart').readAsStringSync();
    expect(router, isNot(contains('ReviewContributions')));
    expect(router, isNot(contains('ReceivedReviews')));
  });

  test('review receipt destinations and copy are removed', () {
    final destinations = File(
      'lib/domain/attention/destination_map.dart',
    ).readAsStringSync();
    expect(destinations, isNot(contains("'review'")));
    expect(destinations, isNot(contains("'received_reviews'")));

    final offenders = <String>[];
    final receiptKeys = RegExp(
      'review_opened|review_all_packages_in|review_window_cancelled|'
      'received_reviews|updatesFallback(Title|Body)Review',
    );
    for (final file in _dartFiles('lib')) {
      if (file.path.startsWith('lib/ui/l10n/')) continue;
      if (receiptKeys.hasMatch(file.readAsStringSync())) {
        offenders.add(file.path);
      }
    }
    expect(offenders..sort(), isEmpty);

    for (final lang in const ['en', 'ru']) {
      final stale = _arb('l10n/app_$lang.arb').keys.where(
        (k) => RegExp('^updatesFallback(Title|Body)Review').hasMatch(k),
      );
      expect(stale, isEmpty, reason: 'app_$lang.arb');
    }
  });

  test('profile "reviews about me" sliver is removed', () {
    expect(
      File(
        'lib/features/profile_view/ui/widget/reviews_about_me_from_profile_sliver.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'lib/features/profile_view/ui/bloc/profile_reviews_about_me_cubit.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        'test/features/profile_view/reviews_about_me_from_profile_sliver_test.dart',
      ).existsSync(),
      isFalse,
    );
  });

  test('old review integration scenarios are removed', () {
    for (final path in const [
      'integration_test/request_lifecycle_close_review_test.dart',
      'integration_test/request_lifecycle_review_trust_control_test.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  for (final lang in const ['en', 'ru']) {
    test('app_$lang.arb has no evaluation* keys', () {
      final keys = _arb('l10n/app_$lang.arb').keys
          .where((k) => k.replaceFirst('@', '').startsWith('evaluation'))
          .toList();
      expect(keys, isEmpty);
    });

    for (final prefix in const ['evaluation', 'review']) {
      test('app_$lang.arb has no unreferenced $prefix* keys', () {
        final keys = _arb(
          'l10n/app_$lang.arb',
        ).keys.where((k) => !k.startsWith('@') && k.startsWith(prefix));
        final source = _liveLibSource();
        final unreferenced = [
          for (final k in keys)
            if (!RegExp('\\.$k\\b').hasMatch(source)) k,
        ];
        expect(unreferenced, isEmpty);
      });
    }
  }

  test('en and ru ARB files keep the same message keys', () {
    Set<String> keys(String p) =>
        _arb(p).keys.where((k) => !k.startsWith('@')).toSet();
    final en = keys('l10n/app_en.arb');
    final ru = keys('l10n/app_ru.arb');
    expect(en.difference(ru), isEmpty);
    expect(ru.difference(en), isEmpty);
  });

  test('generated l10n API matches the ARB keys', () {
    final arbKeys = _arb(
      'l10n/app_en.arb',
    ).keys.where((k) => !k.startsWith('@')).toSet();
    final generated = _l10nMembers(
      File('lib/ui/l10n/l10n.dart').readAsStringSync(),
    );
    expect(generated.difference(arbKeys), isEmpty, reason: 'stale getters');
    expect(arbKeys.difference(generated), isEmpty, reason: 'missing getters');
    for (final path in const [
      'lib/ui/l10n/l10n_en.dart',
      'lib/ui/l10n/l10n_ru.dart',
    ]) {
      expect(
        _l10nMembers(File(path).readAsStringSync()),
        generated,
        reason: path,
      );
    }
  });

  test('flutter gen-l10n succeeds and matches the checked-in API', () async {
    final tmp = Directory.systemTemp.createTempSync('a23_gen_l10n_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/l10n').createSync();
    Directory('${tmp.path}/lib/ui/l10n').createSync(recursive: true);
    for (final f in Directory('l10n').listSync().whereType<File>()) {
      if (f.path.endsWith('.arb')) {
        f.copySync('${tmp.path}/l10n/${f.uri.pathSegments.last}');
      }
    }
    File('l10n.yaml').copySync('${tmp.path}/l10n.yaml');
    File('${tmp.path}/pubspec.yaml').writeAsStringSync(
      'name: tentura\nenvironment:\n  sdk: ^3.0.0\nflutter:\n  generate: true\n',
    );

    final result = await Process.run('flutter', [
      'gen-l10n',
    ], workingDirectory: tmp.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

    for (final name in const ['l10n', 'l10n_en', 'l10n_ru']) {
      expect(
        _l10nMembers(
          File('${tmp.path}/lib/ui/l10n/$name.dart').readAsStringSync(),
        ),
        _l10nMembers(File('lib/ui/l10n/$name.dart').readAsStringSync()),
        reason: '$name.dart is stale; run flutter gen-l10n',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
