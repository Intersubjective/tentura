@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/gql_nodel_base.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_fact_card.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/fake_beacon_access_guard.dart';

class _Facts extends Fake implements BeaconFactCardRepositoryPort {}

class _Room extends Fake implements BeaconRoomRepositoryPort {}

class _Images extends Fake implements ImageRepositoryPort {}

class _Tasks extends Fake implements TaskRepositoryPort {}

class _Hierarchy extends Fake implements BeaconHierarchyRepositoryPort {}

Future<String> _clientSchema() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:tentura_server/'),
  );
  return File.fromUri(
    lib!.resolve('../../client/lib/data/gql/schema.graphql'),
  ).readAsStringSync();
}

String _bare(String sdl) => sdl.replaceAll(RegExp(r'[\[\]!]'), '').trim();

const _rowFields = [
  'id',
  'beaconId',
  'factText',
  'visibility',
  'pinnedBy',
  'pinnedByTitle',
  'sourceMessageId',
  'status',
  'createdAt',
  'updatedAt',
  'attachmentsJson',
  'revisionSeq',
  'lastEditedBy',
  'lastEditedByTitle',
  'lastEditedAt',
  'otherEditorCount',
  'historyTruncated',
  'originBeaconKind',
  'savedByMe',
];

const _originFields = {
  'available',
  'beaconId',
  'factCardId',
  'beaconKind',
  'changedSinceCopy',
  'canSeeCopiedRevision',
  'copiedRevisionSeq',
};

void main() {
  final query = QueryFactCard(
    beaconFactCardCase: BeaconFactCardCase(
      _Facts(),
      _Room(),
      _Images(),
      _Tasks(),
      _Hierarchy(),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconFactCardOriginSchemaTest'),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> originField() {
    final fields = query.all
        .where((f) => f.name == 'BeaconFactCardOrigin')
        .toList();
    expect(fields, hasLength(1), reason: 'server field BeaconFactCardOrigin');
    return fields.single;
  }

  group('Origin of a copied fact over GraphQL', () {
    test('the server answers BeaconFactCardOrigin(beaconId, factCardId) with '
        'exactly the origin fields', () {
      final field = originField();
      expect(
        {for (final a in field.inputs) a.name: a.type.toString()},
        {'beaconId': 'String!', 'factCardId': 'String!'},
      );
      var answer = field.type;
      if (answer is GraphQLNonNullableType) answer = answer.ofType;
      expect(answer, isA<GraphQLObjectType>());
      expect({
        for (final f in (answer as GraphQLObjectType).fields) f.name,
      }, _originFields);
    });

    test('a fact row carries the origin Request kind but never the origin '
        'fact id', () {
      final names = [for (final f in gqlTypeBeaconFactCardRow.fields) f.name];
      expect(names.toSet(), _rowFields.toSet());
      expect(
        names.where((n) => n.toLowerCase().contains('originfactcard')),
        isEmpty,
      );
      final kind = gqlTypeBeaconFactCardRow.fields.firstWhere(
        (f) => f.name == 'originBeaconKind',
      );
      expect(kind.type.toString(), 'Int', reason: 'nullable integer');
    });

    test('the client schema copy declares the same query, arguments, answer '
        'fields and row kind field', () async {
      final schema = await _clientSchema();
      final line = RegExp(
        r'^\s*BeaconFactCardOrigin\(([^)]*)\):\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(schema);
      expect(
        line,
        isNotNull,
        reason: 'client schema lacks BeaconFactCardOrigin',
      );
      expect(
        {
          for (final part in line!.group(1)!.split(','))
            part.split(':').first.trim(): part.split(':').last.trim(),
        },
        {'beaconId': 'String!', 'factCardId': 'String!'},
      );

      final answerType = _bare(line.group(2)!);
      final block = RegExp(
        'type ${RegExp.escape(answerType)} \\{([^}]*)\\}',
      ).firstMatch(schema);
      expect(block, isNotNull, reason: 'client schema lacks $answerType');
      expect({
        for (final m in RegExp(
          r'^\s*(\w+):',
          multiLine: true,
        ).allMatches(block!.group(1)!))
          m.group(1)!,
      }, _originFields);

      // The row type is whatever the client's list query returns.
      final listLine = RegExp(
        r'^\s*BeaconFactCardList\([^)]*\):\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(schema);
      expect(listLine, isNotNull, reason: 'client schema lacks the list query');
      final rowType = _bare(listLine!.group(1)!);
      final row = RegExp(
        'type ${RegExp.escape(rowType)} \\{([^}]*)\\}',
      ).firstMatch(schema);
      expect(row, isNotNull, reason: 'client schema lacks $rowType');
      expect(row!.group(1), matches(RegExp(r'originBeaconKind:\s*Int\s')));
      expect({
        for (final m in RegExp(
          r'^\s*(\w+):',
          multiLine: true,
        ).allMatches(row.group(1)!))
          m.group(1)!,
      }, _rowFields.toSet());
      expect(
        row.group(1)!.toLowerCase().contains('originfactcard'),
        false,
      );
    });
  });
}
