// Subprocess fixture for the client's populated-tag deletion widget test.
// The client sends its actual Ferry request over stdin. Only the transport
// and authentication are substituted; the resolver, use case and DB are real.
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/people_tags_case.dart';
import 'package:tentura_server/env.dart';

import 'disposable_pg_target.dart';

const _owner = 'Udeleteowner001';
const _member = 'Udeletemember01';

void _reply(Object value) => stdout.writeln('fixture:${jsonEncode(value)}');

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAG_DELETE_WIDGET_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tag_delete_widget',
  );
  final session = await setUpDisposablePgWriter(target: target);
  try {
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    for (final id in [_owner, _member]) {
      await session.writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': id, 'key': '$id-key'},
      );
    }
    final tags = getIt<PeopleTagsCase>();
    final tag = await tags.create(
      ownerId: _owner,
      name: 'Neighbours',
      clientOpId: 'create',
    );
    await tags.applyMembers(
      ownerId: _owner,
      ops: [
        {'tagId': tag.id, 'personId': _member, 'op': 'add', 'source': 2},
      ],
      clientOpId: 'add-member',
    );
    final schema = graphqlSchema;
    final before = await tags.list(ownerId: _owner);
    _reply({'tag': before.single.toGraphQL(), 'memberId': _member});

    final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      final request = jsonDecode(line) as Map<String, dynamic>;
      try {
        final data = await schema.parseAndExecute(
          request['query']! as String,
          variableValues: Map<String, dynamic>.from(
            request['variables']! as Map,
          ),
          globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: _owner)},
        );
        _reply({'data': data});
      } on GraphQLException catch (error) {
        // Match the production controller's GraphQL error envelope.
        _reply(error.toJson());
      }
    }
  } finally {
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  }
}
