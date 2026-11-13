@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

Future<String> _readFromRepo(String relativeToServerLib) async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:tentura_server/'),
  );
  return File.fromUri(lib!.resolve(relativeToServerLib)).readAsStringSync();
}

// A real declaration line (not a comment), with or without an explicit type.
final _declaresFactsBrought = matches(
  RegExp(r'^\s*static const (int )?factsBrought = 20;', multiLine: true),
);

void main() {
  group('thread message preview fact count', () {
    test('the server preview type exposes a nullable Int factCount', () {
      final field = gqlTypeThreadMessagePreview.fields
          .where((f) => f.name == 'factCount')
          .toList();
      expect(field, hasLength(1));
      expect(field.single.type.toString(), 'Int');
    });

    test('the client schema copy declares factCount on the preview type',
        () async {
      final schema = await _readFromRepo(
        '../../client/lib/data/gql/schema.graphql',
      );
      final block = RegExp(
        r'type v2_ThreadMessagePreview \{([^}]*)\}',
      ).firstMatch(schema)!.group(1)!;
      expect(block, contains(RegExp(r'^\s*factCount: Int\s*$', multiLine: true)));
    });
  });

  group('facts-brought chat marker constant', () {
    test('is 20 in the server consts', () async {
      final src = await _readFromRepo('consts/beacon_room_consts.dart');
      expect(src, _declaresFactsBrought);
    });

    test('is 20 in the client consts', () async {
      final src = await _readFromRepo(
        '../../client/lib/domain/entity/beacon_room_consts.dart',
      );
      expect(src, _declaresFactsBrought);
    });
  });
}
