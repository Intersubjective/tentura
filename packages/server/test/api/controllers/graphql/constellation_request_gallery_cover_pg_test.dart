@Tags(['pg', 'mr'])
library;

import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field_requests.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_requests_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_profile_batch_lookup.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/domain/use_case/constellation_field_requests_case.dart';

import '../../../support/disposable_pg_target.dart';

const _author = 'Ucoverauthor1';
const _recipient = 'Ucoverreader1';
const _covered = 'Bcoverphoto01';
const _uncovered = 'Bcoverempty01';
const _cropped = 'Bcovercrop001';
const _firstImage = 'e05babc2-d45d-48c2-86f1-dcf84e69ddaf';
const _selectedImage = '847c6b63-f13a-4153-8f70-0c9778e20716';
const _croppedGallery = '01c7bef6-572c-43f0-95ef-eed1f51137cc';
const _thumbImage = '0b05206d-9f7a-457a-a59a-c818ec11b8fc';
const _imageFields = 'id hash width height author_id';
const _requestFields = 'id coverSource coverThumb { $_imageFields }';
const _coverFields = 'coverImage { $_imageFields }';
const _expectedCover = {
  'id': _selectedImage,
  'hash': 'selected-cover-hash',
  'width': 960,
  'height': 640,
  'author_id': _author,
};

const _expectedCroppedGallery = {
  'id': _croppedGallery,
  'hash': 'uncropped-cover-hash',
  'width': 800,
  'height': 600,
  'author_id': _author,
};
const _expectedThumb = {
  'id': _thumbImage,
  'hash': 'cropped-cover-hash',
  'width': 128,
  'height': 128,
  'author_id': _author,
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_GALLERY_COVER_TEST_DB',
    defaultNamePrefix: 'tentura_test_field_gallery_cover',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late GraphQL schema;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    final db = openDisposablePgDatabase(target);
    addTearDown(() => tearDownDisposablePgWriter(session: session, drift: db));
    final field = QueryConstellationField(
      constellationFieldCase: ConstellationFieldCase(
        ConstellationFieldRepository(
          db,
          DriftUserProfileBatchLookup(db, UserAvailabilityRepository(db)),
        ),
        env: target.databaseEnv,
        logger: Logger('gallery-cover'),
      ),
    );
    final targeted = QueryConstellationFieldRequests(
      case_: ConstellationFieldRequestsCase(
        ConstellationFieldRequestsRepository(db),
        env: target.databaseEnv,
        logger: Logger('gallery-cover'),
      ),
    );
    schema = TenturaGraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', null)
          ..fields.addAll([...field.all, ...targeted.all]),
      ),
      customTypes: customTypes,
    );

    final writer = session.writer;
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key) VALUES
  ('$_author', 'Cover author', 'author-key'),
  ('$_recipient', 'Forward recipient', 'recipient-key')
''');
    await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, kind, is_discoverable,
  published_at, cover_source
) VALUES
  ('$_covered', '$_author', 'Selected cover', 'Request', 0, 0, true, now(), 0),
  ('$_uncovered', '$_author', 'No cover', 'Request', 0, 0, true, now(), 0),
  ('$_cropped', '$_author', 'Cropped cover', 'Request', 0, 0, true, now(), 0)
''');
    await writer.execute('''
INSERT INTO public.image (id, author_id, hash, width, height) VALUES
  ('$_firstImage', '$_author', 'first-gallery-hash', 100, 120),
  ('$_selectedImage', '$_author', 'selected-cover-hash', 960, 640),
  ('$_thumbImage', '$_author', 'cropped-cover-hash', 128, 128),
  ('$_croppedGallery', '$_author', 'uncropped-cover-hash', 800, 600)
''');
    await writer.execute('''
INSERT INTO public.beacon_image (beacon_id, image_id, position) VALUES
  ('$_covered', '$_firstImage', 0),
  ('$_covered', '$_selectedImage', 1),
  ('$_cropped', '$_croppedGallery', 0)
''');
    await writer.execute('''
UPDATE public.beacon SET cover_image_id = '$_selectedImage'
WHERE id = '$_covered'
''');
    await writer.execute('''
UPDATE public.beacon
SET cover_image_id = '$_croppedGallery', cover_thumb_image_id = '$_thumbImage'
WHERE id = '$_cropped'
''');
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES ('$_covered', '$_author', '$_recipient'),
       ('$_uncovered', '$_author', '$_recipient'),
       ('$_cropped', '$_author', '$_recipient')
''');
    await writer.executeWithOwnerScopes(
      [_author],
      Sql.named(
        'INSERT INTO public.constellation_anchor_cursor (viewer_id) '
        'VALUES (@author)',
      ),
      parameters: {'author': _author},
    );
    await writer.executeWithOwnerScopes(
      [_author],
      Sql.named('''
INSERT INTO public.constellation_anchor (id, viewer_id, beacon_id, x_units,
  y_units, coordinate_space_version, revision, placed_at)
VALUES ('CAcoverphoto1', @author, @covered, 1, 1, 1, 1, now()),
       ('CAcoverempty1', @author, @uncovered, 2, 2, 1, 2, now()),
       ('CAcovercrop01', @author, @cropped, 3, 3, 1, 3, now())
'''),
      parameters: {
        'author': _author,
        'covered': _covered,
        'uncovered': _uncovered,
        'cropped': _cropped,
      },
    );
  });

  Future<Map<String, dynamic>> run(String query, String viewer) async =>
      await schema.parseAndExecute(
            query,
            globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
          )
          as Map<String, dynamic>;

  Future<List<dynamic>> requests(String selection) async {
    final result = await run(
      '{ constellationField(projection: FULL) { requests { $selection } } }',
      _author,
    );
    return (result['constellationField'] as Map)['requests'] as List;
  }

  Future<List<dynamic>> pinnedRequests(String selection) async {
    final result = await run(
      '{ constellationField(projection: FULL) { '
      'anchorProjection { pinnedRequests { $selection } } } }',
      _author,
    );
    final field = result['constellationField'] as Map;
    return (field['anchorProjection'] as Map)['pinnedRequests'] as List;
  }

  Future<List<dynamic>> targetedRequests(String selection) async {
    final result = await run(
      '{ constellationFieldRequests(ids: ["$_covered", "$_uncovered", "$_cropped"]) '
      '{ $selection } }',
      _recipient,
    );
    return result['constellationFieldRequests'] as List;
  }

  for (final (surface, fetch) in [
    ('Field Requests', requests),
    ('pinned Field Requests', pinnedRequests),
    ('targeted Field Requests', targetedRequests),
  ]) {
    test(
      '$surface return the gallery cover and cropped thumb as separate images',
      () async {
        final existing = [
          {'id': _covered, 'coverSource': 0, 'coverThumb': null},
          {'id': _uncovered, 'coverSource': 0, 'coverThumb': null},
          {'id': _cropped, 'coverSource': 0, 'coverThumb': _expectedThumb},
        ];
        expect(await fetch(_requestFields), unorderedEquals(existing));

        expect(
          await fetch('$_requestFields $_coverFields'),
          unorderedEquals([
            for (final row in existing)
              {
                ...row,
                'coverImage': switch (row['id']) {
                  _covered => _expectedCover,
                  _cropped => _expectedCroppedGallery,
                  _ => null,
                },
              },
          ]),
        );
      },
    );
  }
}
