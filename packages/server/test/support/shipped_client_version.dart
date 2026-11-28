import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

void expectShippedClientMeetsServerMinimum() {
  final release =
      Pubspec.parse(
        File('../client/pubspec.yaml').readAsStringSync(),
      ).version ??
      fail('The client pubspec must declare a release version.');
  expect(
    release,
    greaterThanOrEqualTo(Version.parse(kDefaultMinClientVersion)),
  );
}
