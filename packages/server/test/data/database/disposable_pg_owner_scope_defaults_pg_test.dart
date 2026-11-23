@Tags(['pg'])
@Timeout(Duration(minutes: 2))
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

const _owner = 'Uscopeowner01';
const _peer = 'Uscopepeer001';
const _setOwnerScope = "SET LOCAL tentura.owner_scopes = '[\"$_owner\"]'";

Future<Connection> _open(DisposablePgTarget target) async {
  final connection = await Connection.open(
    target.databaseEnv.pgEndpoint,
    settings: target.databaseEnv.pgEndpointSettings,
  );
  addTearDown(connection.close);
  return connection;
}

Future<Object?> _enforcement(Connection connection) async =>
    (await connection.execute(
      "SELECT current_setting('tentura.owner_scope_enforce', true)",
    )).single.single;

Future<Result> _insertTag(Session session, String id) => session.execute(
  Sql.named('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES (@id, @owner, @id, 'T', 0, 1)
'''),
  parameters: {'id': id, 'owner': _owner},
);

Matcher _scopeRequired(String table) => throwsA(
  isA<ServerException>().having(
    (error) => error.message,
    'message',
    contains('Owner scope required for INSERT on public.$table'),
  ),
);

Future<void> main() async {
  final cloned = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OWNER_SCOPE_CLONE_TEST_DB',
    defaultNamePrefix: 'tentura_test_owner_scope_clone',
  );
  final withoutTemplate = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OWNER_SCOPE_NO_TEMPLATE_TEST_DB',
    defaultNamePrefix: 'tentura_test_owner_scope_no_template',
  );
  final skipReason = await pgSkipReason(cloned);

  group('Default owner scope enforcement in disposable PostgreSQL', () {
    group('database recreation', () {
      setUpAll(() async {
        await cloned.recreate();
        addTearDown(cloned.drop);
      });

      test(
        'a fresh connection after recreating a database enforces scopes',
        () async {
          expect(await _enforcement(await _open(cloned)), 'on');
        },
      );
    });

    group('database creation without the template', () {
      setUpAll(() async {
        final session = await setUpDisposablePgWriter(
          target: withoutTemplate,
          lastInclusiveVersion: migrationsForTesting.last.version,
        );
        addTearDown(() => tearDownDisposablePgWriter(session: session));
      });

      test('a fresh connection to a database built without the template '
          'enforces scopes', () async {
        expect(await _enforcement(await _open(withoutTemplate)), 'on');
      });
    });

    group('template clone', () {
      setUpAll(() async {
        final session = await setUpDisposablePgWriter(target: cloned);
        addTearDown(() => tearDownDisposablePgWriter(session: session));
        await session.writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@owner, 'Owner', 'scope-owner-key'), (@peer, 'Peer', 'scope-peer-key')
'''),
          parameters: {'owner': _owner, 'peer': _peer},
        );
        await session.writer.runTx((tx) async {
          await tx.execute(_setOwnerScope);
          await tx.execute(
            Sql.named('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES (@owner)
'''),
            parameters: {'owner': _owner},
          );
        });
      });

      test('a fresh connection to a template clone enforces scopes', () async {
        expect(await _enforcement(await _open(cloned)), 'on');
      });

      test('a tag insert requires a matching transaction scope', () async {
        final scoped = await _open(cloned);
        await scoped.runTx((tx) async {
          await tx.execute(_setOwnerScope);
          await _insertTag(tx, 'scoped-tag');
        });

        final unscoped = await _open(cloned);
        final saved = await unscoped.execute('''
SELECT owner_id FROM public.person_tag WHERE id = 'scoped-tag'
''');
        expect(saved.single.single, _owner);
        await expectLater(
          unscoped.runTx((tx) => _insertTag(tx, 'unscoped-tag')),
          _scopeRequired('person_tag'),
        );
      });

      test('an anchor insert requires its viewer in the scope', () async {
        final unscoped = await _open(cloned);

        await expectLater(
          unscoped.execute(
            Sql.named('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, person_id, x_units, y_units,
   coordinate_space_version, revision, placed_at)
VALUES ('unscoped-anchor', @owner, @peer, 1, 1, 1, 0, now())
'''),
            parameters: {'owner': _owner, 'peer': _peer},
          ),
          _scopeRequired('constellation_anchor'),
        );
      });
    });
  }, skip: skipReason);
}
