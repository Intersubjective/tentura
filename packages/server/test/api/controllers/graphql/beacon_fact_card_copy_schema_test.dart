@Tags(['repo-files'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/gql_nodel_base.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_fact_card.dart';
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

/// A GraphQL type as SDL prints it (wrappers included).
String _sdl(Object type) => type.toString();

String _bare(String sdl) => sdl.replaceAll(RegExp(r'[\[\]!]'), '').trim();

void main() {
  final mutation = MutationFactCard(
    beaconFactCardCase: BeaconFactCardCase(
      _Facts(),
      _Room(),
      _Images(),
      _Tasks(),
      _Hierarchy(),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconFactCardCopySchemaTest'),
    ),
  );

  group('Copying a fact into another Request over GraphQL', () {
    GraphQLObjectField<dynamic, dynamic> copyField() {
      final fields = mutation.all
          .where((f) => f.name == 'BeaconFactCardCopy')
          .toList();
      expect(fields, hasLength(1), reason: 'server field BeaconFactCardCopy');
      return fields.single;
    }

    test('the server exposes BeaconFactCardCopy(sourceFactCardId: String!, '
        'destinationBeaconId: String!) answering factCardId and an outcome of '
        'created or alreadyThere', () {
      final field = copyField();
      expect(
        {for (final a in field.inputs) a.name: _sdl(a.type)},
        {'sourceFactCardId': 'String!', 'destinationBeaconId': 'String!'},
      );

      var answer = field.type;
      if (answer is GraphQLNonNullableType) answer = answer.ofType;
      expect(answer, isA<GraphQLObjectType>(), reason: 'answer is an object');
      final answerFields = {
        for (final f in (answer as GraphQLObjectType).fields) f.name: f.type,
      };
      expect(answerFields.keys, containsAll(['factCardId', 'outcome']));
      expect(_bare(_sdl(answerFields['factCardId']!)), 'String');

      var outcome = answerFields['outcome']!;
      if (outcome is GraphQLNonNullableType) outcome = outcome.ofType;
      if (outcome is GraphQLEnumType) {
        expect(
          [for (final v in outcome.values) v.name],
          unorderedEquals(['created', 'alreadyThere']),
        );
      } else {
        expect(_bare(_sdl(outcome)), 'String');
      }
    });

    test('the client schema copy declares the same mutation, arguments and '
        'answer fields as the server', () async {
      final schema = await _clientSchema();
      var serverAnswer = copyField().type;
      if (serverAnswer is GraphQLNonNullableType) {
        serverAnswer = serverAnswer.ofType;
      }
      expect(serverAnswer, isA<GraphQLObjectType>());
      final serverFields = {
        for (final f in (serverAnswer as GraphQLObjectType).fields) f.name,
      };

      final line = RegExp(
        r'^\s*BeaconFactCardCopy\(([^)]*)\):\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(schema);
      expect(line, isNotNull, reason: 'client schema lacks BeaconFactCardCopy');
      final clientArgs = {
        for (final part in line!.group(1)!.split(','))
          part.split(':').first.trim(): part.split(':').last.trim(),
      };
      expect(clientArgs, {
        'sourceFactCardId': 'String!',
        'destinationBeaconId': 'String!',
      });

      final answerType = _bare(line.group(2)!);
      final block = RegExp(
        'type ${RegExp.escape(answerType)} \\{([^}]*)\\}',
      ).firstMatch(schema);
      expect(block, isNotNull, reason: 'client schema lacks $answerType');
      final clientFields = <String, String>{
        for (final m in RegExp(
          r'^\s*(\w+):\s*(\S+)\s*$',
          multiLine: true,
        ).allMatches(block!.group(1)!))
          m.group(1)!: m.group(2)!,
      };
      expect(clientFields.keys.toSet(), serverFields);
      expect(_bare(clientFields['factCardId']!), 'String');

      final outcomeType = _bare(clientFields['outcome']!);
      if (outcomeType != 'String') {
        final values = RegExp(
          'enum ${RegExp.escape(outcomeType)} \\{([^}]*)\\}',
        ).firstMatch(schema);
        expect(values, isNotNull, reason: 'outcome enum $outcomeType missing');
        expect(
          values!.group(1)!.split(RegExp(r'\s+')).where((v) => v.isNotEmpty),
          unorderedEquals(['created', 'alreadyThere']),
        );
      }
    });
  });
}
