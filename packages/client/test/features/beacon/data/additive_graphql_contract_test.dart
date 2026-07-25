import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String schema;

  setUpAll(() {
    schema = File('lib/data/gql/schema.graphql').readAsStringSync();
  });

  group('additive GraphQL contract', () {
    test('schema exposes cover fields and stage/media operations', () {
      expect(schema, contains('primaryNeedSlug: String'));
      expect(schema, contains('coverImageId: String'));
      expect(schema, contains('coverSource: Int!'));
      expect(schema, contains('beaconStageImage('));
      expect(schema, contains('beaconSetMedia('));
      expect(schema, contains('type v2_BeaconImageAdded {'));
      expect(schema, contains('type v2_BeaconImageStaged {'));
      expect(schema, contains('imageId: String!'));
      expect(schema, isNot(contains('beaconSetCover')));
    });

    // Server declares input Upload; Hasura stitches it to v2_Upload. The
    // fetched schema must expose only the stitched name — never a hand-added
    // bare `input Upload` alias beside it.
    test('schema exposes stitched v2_Upload only (no hand-added Upload)', () {
      expect(schema, contains('input v2_Upload {'));
      expect(schema, isNot(contains('input Upload {')));
      expect(
        File('lib/features/beacon/data/gql/beacon_stage_image.graphql')
            .readAsStringSync(),
        contains(r'$image: v2_Upload'),
      );
      expect(
        File('lib/features/beacon/data/gql/beacon_add_image.graphql')
            .readAsStringSync(),
        contains(r'$image: v2_Upload'),
      );
    });

    test('schema and client documents omit legacy icon arguments', () {
      expect(schema, isNot(contains('iconCode: String')));
      expect(schema, isNot(contains('iconBackground: Int')));
      expect(schema, isNot(contains('icon_code')));
      expect(schema, isNot(contains('icon_background')));

      for (final relative in [
        'lib/features/beacon/data/gql/beacon_create.graphql',
        'lib/features/beacon/data/gql/beacon_update.graphql',
        'lib/features/beacon/data/gql/beacon_update_draft.graphql',
      ]) {
        final doc = File(relative).readAsStringSync();
        expect(doc, isNot(contains('iconCode')), reason: relative);
        expect(doc, isNot(contains('iconBackground')), reason: relative);
      }
      expect(
        File('lib/data/gql/beacon_model.graphql').readAsStringSync(),
        isNot(contains('icon_')),
      );
    });

    test('legacy create/update/add documents still validate against schema', () {
      for (final relative in [
        'lib/features/beacon/data/gql/beacon_create.graphql',
        'lib/features/beacon/data/gql/beacon_update.graphql',
        'lib/features/beacon/data/gql/beacon_update_draft.graphql',
        'lib/features/beacon/data/gql/beacon_add_image.graphql',
      ]) {
        final doc = File(relative).readAsStringSync();
        expect(doc, contains('mutation '), reason: relative);
        expect(doc, isNot(contains('beaconSetCover')), reason: relative);
      }
      expect(
        File('lib/features/beacon/data/gql/beacon_create.graphql')
            .readAsStringSync(),
        contains(r'$primaryNeedSlug'),
      );
      expect(
        File('lib/features/beacon/data/gql/beacon_add_image.graphql')
            .readAsStringSync(),
        contains('imageId'),
      );
    });

    test('new stage/media documents exist', () {
      expect(
        File('lib/features/beacon/data/gql/beacon_stage_image.graphql').existsSync(),
        isTrue,
      );
      expect(
        File('lib/features/beacon/data/gql/beacon_set_media.graphql').existsSync(),
        isTrue,
      );
      final setMedia = File(
        'lib/features/beacon/data/gql/beacon_set_media.graphql',
      ).readAsStringSync();
      expect(setMedia, contains(r'$coverSource: Int!'));
      expect(setMedia, contains(r'$imageIds: [String!]'));
    });
  });
}
