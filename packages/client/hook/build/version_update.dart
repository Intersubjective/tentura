// ignore_for_file: avoid_print //

import 'dart:io';
import 'dart:convert';
import 'package:html/parser.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:pretty_print_json/pretty_print_json.dart';

void versionUpdate() {
  final pubspec = Pubspec.parse(
    File('pubspec.yaml').readAsStringSync(),
  );
  final version = pubspec.version.toString();
  print('Current version: $version');

  final manifestJsonFile = File('web/manifest.json');
  final manifestJson =
      jsonDecode(manifestJsonFile.readAsStringSync()) as Map<String, dynamic>;

  if (manifestJson['version'] != version) {
    manifestJson['version'] = version;
    manifestJsonFile.writeAsStringSync(
      prettyJson(manifestJson),
      flush: true,
    );
    print('Updated manifest.json');
  }

  final indexHtmlFile = File('web/index.html');
  final document = parse(indexHtmlFile.readAsStringSync());
  final scriptElement = document
      .getElementsByTagName('script')
      .singleWhere(
        (e) => e.attributes['src']?.startsWith('flutter_bootstrap.js') ?? false,
      );

  if (!(scriptElement.attributes['src']?.endsWith(version) ?? false)) {
    scriptElement.attributes['src'] = 'flutter_bootstrap.js?v=$version';
    indexHtmlFile.writeAsStringSync(
      document.outerHtml,
      flush: true,
    );
    print('Updated index.html');
  }
}
