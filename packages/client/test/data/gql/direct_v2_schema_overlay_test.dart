import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // schema.graphql is produced by `docker compose run --rm schema_fetcher`
  // against live Hasura. Do not hand-add aliases: Hasura remote-schema
  // stitching already prefixes Tentura V2 inputs (`Coordinates` →
  // `v2_Coordinates`, `Upload` → `v2_Upload`). Client documents must use
  // those stitched names. Hasura `user` exposes `display_name` (snake_case).
  test(
    'fetched schema exposes stitched V2 inputs and review-extension types',
    () {
      final schema = File('lib/data/gql/schema.graphql').readAsStringSync();

      expect(schema, contains('input v2_Coordinates {'));
      expect(schema, isNot(contains('input Coordinates {')));
      expect(schema, contains('coordinates: v2_Coordinates = {}'));
      expect(schema, contains('input v2_Upload {'));
      expect(schema, isNot(contains('input Upload {')));
      expect(
        schema,
        contains(
          'beaconExtendReview(id: String!): '
          'v2_BeaconExtendReviewResult!',
        ),
      );
      expect(schema, contains('type v2_BeaconExtendReviewResult {'));
      expect(schema, contains('extensionsRemaining: Int!'));
      expect(
        schema,
        contains('forwardCandidates(context: String!): [v2_user!]!'),
      );

      final userStart = schema.indexOf('type user {');
      final userEnd = schema.indexOf('input user_bool_exp', userStart);
      expect(userStart, isNonNegative);
      expect(userEnd, greaterThan(userStart));
      final userType = schema.substring(userStart, userEnd);
      expect(userType, contains('display_name: String!'));
      expect(userType, isNot(contains('displayName: String!')));

      expect(
        schema,
        contains(
          'constellationField(participatedOnly: Boolean! = false, '
          'projection: v2_ConstellationProjection! = FULL, '
          'showClosed: Boolean! = false): v2_ConstellationField!',
        ),
      );
      expect(schema, contains('type v2_ConstellationAnchor {'));
      expect(schema, contains('type v2_ConstellationAnchorProjection {'));
      expect(schema, contains('enum v2_ConstellationProjection {'));
      expect(schema, contains('enum v2_ConstellationAnchorTargetKind {'));
      expect(
        schema,
        contains(
          'constellationAnchorUpsert(coordinateSpaceVersion: Int!, '
          'targetId: String!, targetKind: v2_ConstellationAnchorTargetKind!, '
          'xUnits: Float!, yUnits: Float!): v2_ConstellationAnchorUpsertResult!',
        ),
      );
      expect(
        schema,
        contains(
          'constellationAnchorDelete(targetId: String!, '
          'targetKind: v2_ConstellationAnchorTargetKind!): '
          'v2_ConstellationAnchorDeleteResult!',
        ),
      );
    },
  );

  test('fetched schema exposes MarkBeaconPeopleSeen and authorSeenAt', () {
    final schema = File('lib/data/gql/schema.graphql').readAsStringSync();

    expect(
      schema,
      contains(
        'MarkBeaconPeopleSeen(beaconId: String!, readThroughAt: String): '
        'v2_BeaconPeopleSeenResult!',
      ),
    );
    expect(schema, contains('type v2_BeaconPeopleSeenResult {'));

    final rowStart = schema.indexOf('type v2_HelpOfferWithCoordinationRow {');
    expect(rowStart, isNonNegative);
    final rowEnd = schema.indexOf('\n}', rowStart);
    expect(
      schema.substring(rowStart, rowEnd),
      contains('authorSeenAt: String'),
    );
  });

  // Issue #181 plan §8.11 / §14.2: schema.graphql is hand-edited to mirror
  // server `custom_types.dart` + `mutation_fact_card.dart` names and
  // nullability character for character. Hasura stitching sorts fields and
  // arguments alphabetically and prefixes V2 object types with `v2_`.
  //
  // `BeaconFactCardRevisions` has no server GraphQL type yet, so only the
  // plan §8.11 contract is pinned: `(beaconId, factCardId, before: String)`
  // → `{entries, nextCursor: String?}`. The entry row type is whatever the
  // server ships; this test only requires that it exists.
  group('fact revision history (issue #181)', () {
    late String schema;

    setUpAll(() {
      schema = File('lib/data/gql/schema.graphql').readAsStringSync();
    });

    /// The full `type [name] { ... }` definition, including the closing
    /// brace.
    String typeDefinition(String name) {
      final start = schema.indexOf('type $name {');
      expect(start, isNonNegative, reason: 'type $name is missing');
      expect(
        schema.indexOf('type $name {', start + 1),
        isNegative,
        reason: 'type $name is defined twice',
      );
      final end = schema.indexOf('\n}', start);
      return schema.substring(start, end + 2);
    }

    /// Field lines of a root type (`mutation_root`, `query_root`) that
    /// start with [fieldName] followed by `(`; `.single` on the result
    /// rejects a missing or duplicated field.
    List<String> rootFields(String root, String fieldName) =>
        typeDefinition(root)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.startsWith('$fieldName('))
            .toList();

    test('v2_BeaconFactCardRow matches custom_types gqlTypeBeaconFactCardRow '
        'exactly', () {
      expect(
        typeDefinition('v2_BeaconFactCardRow'),
        'type v2_BeaconFactCardRow {\n'
        '  attachmentsJson: String!\n'
        '  beaconId: String!\n'
        '  createdAt: String!\n'
        '  factText: String!\n'
        '  historyTruncated: Boolean!\n'
        '  id: String!\n'
        '  lastEditedAt: String\n'
        '  lastEditedBy: String\n'
        '  lastEditedByTitle: String\n'
        '  otherEditorCount: Int!\n'
        '  pinnedBy: String!\n'
        '  pinnedByTitle: String!\n'
        '  revisionSeq: Int!\n'
        '  sourceMessageId: String\n'
        '  status: Int!\n'
        '  updatedAt: String\n'
        '  visibility: Int!\n'
        '}',
      );
    });

    test('BeaconFactCardList signature is unchanged', () {
      expect(rootFields('query_root', 'BeaconFactCardList'), [
        'BeaconFactCardList(beaconId: String!): [v2_BeaconFactCardRow!]',
      ]);
    });

    test('BeaconFactCardCorrect takes baseRevisionSeq and returns Int!', () {
      expect(
        rootFields('mutation_root', 'BeaconFactCardCorrect').single,
        'BeaconFactCardCorrect(baseRevisionSeq: Int!, beaconId: String!, '
        'factCardId: String!, newText: String!): Int!',
      );
    });

    test('BeaconFactCardRestore takes fromSeq + baseRevisionSeq and returns '
        'Int!', () {
      expect(
        rootFields('mutation_root', 'BeaconFactCardRestore').single,
        'BeaconFactCardRestore(baseRevisionSeq: Int!, beaconId: String!, '
        'factCardId: String!, fromSeq: Int!): Int!',
      );
    });

    test('BeaconFactCardRemove / SetVisibility signatures are unchanged', () {
      expect(
        rootFields('mutation_root', 'BeaconFactCardRemove').single,
        'BeaconFactCardRemove(beaconId: String!, factCardId: String!): '
        'Boolean!',
      );
      expect(
        rootFields('mutation_root', 'BeaconFactCardSetVisibility').single,
        'BeaconFactCardSetVisibility(beaconId: String!, '
        'factCardId: String!, visibility: Int!): Boolean!',
      );
    });

    test('BeaconFactCardRevisions(beaconId, factCardId, before: String) '
        'returns {entries, nextCursor: String}', () {
      final field = rootFields('query_root', 'BeaconFactCardRevisions').single;
      final signature = RegExp(
        r'^BeaconFactCardRevisions\(before: String, beaconId: String!, '
        r'factCardId: String!\): (v2_\w+)!?$',
      ).firstMatch(field);
      expect(signature, isNotNull, reason: field);

      final pageName = signature!.group(1)!;
      final page = typeDefinition(pageName);
      final pageFields = page
          .split('\n')
          .skip(1)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l != '}')
          .toList();
      expect(pageFields, hasLength(2), reason: page);
      expect(pageFields, contains('nextCursor: String'));
      final entries = RegExp(
        r'^entries: \[(v2_\w+)!\]!$',
      ).firstMatch(pageFields.firstWhere((l) => l.startsWith('entries:')));
      expect(entries, isNotNull, reason: page);
      typeDefinition(entries!.group(1)!);
    });
  });

  // Issue #181 plan §8.11: RoomMessageList rows carry the quoted fact
  // snapshot (server `gqlTypeRoomMessageQuotedFact`) and RoomMessageCreate
  // takes the quote ids. Hasura sorts fields/arguments alphabetically and
  // prefixes V2 object types with `v2_`.
  group('room message quoted fact (issue #181)', () {
    late String schema;

    setUpAll(() {
      schema = File('lib/data/gql/schema.graphql').readAsStringSync();
    });

    String typeDefinition(String name) {
      final start = schema.indexOf('type $name {');
      expect(start, isNonNegative, reason: 'type $name is missing');
      expect(
        schema.indexOf('type $name {', start + 1),
        isNegative,
        reason: 'type $name is defined twice',
      );
      final end = schema.indexOf('\n}', start);
      return schema.substring(start, end + 2);
    }

    /// SDL for server `custom_types.dart` object type [dartName] as Hasura
    /// stitches it: `v2_` prefix, fields sorted alphabetically.
    String serverTypeAsStitchedSdl(String dartName) {
      final source = File(
        '../server/lib/api/controllers/graphql/custom_types.dart',
      ).readAsStringSync();
      final start = source.indexOf('final $dartName =');
      expect(start, isNonNegative, reason: '$dartName is missing on server');
      final end = source.indexOf(']);', start);
      final body = source.substring(start, end);
      final typeName = RegExp(
        r"GraphQLObjectType\('(\w+)'",
      ).firstMatch(body)!.group(1)!;
      const scalars = {
        'graphQLString': 'String',
        'graphQLInt': 'Int',
        'graphQLBoolean': 'Boolean',
        'graphQLFloat': 'Float',
      };
      final fields = RegExp(
        r"field\('(\w+)',\s*(\w+)(\.nonNullable\(\))?\)",
      ).allMatches(body).map((m) {
        final scalar = scalars[m.group(2)!];
        expect(scalar, isNotNull, reason: 'unmapped type ${m.group(2)}');
        return '  ${m.group(1)}: $scalar${m.group(3) == null ? '' : '!'}';
      }).toList()..sort();
      return 'type v2_$typeName {\n${fields.join('\n')}\n}';
    }

    test('v2_RoomMessageQuotedFact matches custom_types '
        'gqlTypeRoomMessageQuotedFact exactly', () {
      final expected = serverTypeAsStitchedSdl('gqlTypeRoomMessageQuotedFact');
      // Guard the server-side parse itself against silently matching nothing.
      expect(expected, contains('  factCardId: String!\n'));
      expect(expected, contains('  pinnedById: String\n'));
      expect(expected.split('\n'), hasLength(11));

      expect(typeDefinition('v2_RoomMessageQuotedFact'), expected);
    });

    test('v2_RoomMessageRow exposes nullable quotedFact in sorted order', () {
      final row = typeDefinition('v2_RoomMessageRow');
      expect(
        row,
        contains(
          '  pollDataJson: String\n'
          '  quotedFact: v2_RoomMessageQuotedFact\n'
          '  reactionsJson: String\n',
        ),
      );
    });

    test('RoomMessageCreate takes optional quotedFactCardId + '
        'quotedFactRevisionSeq', () {
      final fields = typeDefinition('mutation_root')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('RoomMessageCreate('))
          .toList();
      expect(fields, [
        'RoomMessageCreate(beaconId: String!, body: String!, '
            'explicitMentionLengths: [Int!], explicitMentionOffsets: [Int!], '
            'explicitMentionUserIds: [String!], file: v2_Upload, '
            'quotedFactCardId: String, quotedFactRevisionSeq: Int, '
            'replyToMessageId: String, threadItemId: String): '
            'v2_RoomMessageCreatePayload!',
      ]);
    });
  });
}
