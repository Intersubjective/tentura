import 'package:ferry/ferry.dart'
    show Client, DataSource, FetchPolicy, Link, NextLink, OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;

import 'package:tentura/data/service/remote_api_client/beacon_hierarchy_error_mapper.dart';
import 'package:tentura/data/service/remote_api_service.dart' show ErrorHandler;
import 'package:tentura/features/beacon/data/gql/_g/beacon_child_create.req.gql.dart';
import 'package:tentura/features/beacon/data/gql/_g/beacon_children.req.gql.dart';
import 'package:tentura/features/beacon/data/gql/_g/beacon_hierarchy_capabilities.req.gql.dart';
import 'package:tentura/features/beacon/data/gql/_g/beacon_parent_reference.req.gql.dart';
import 'package:tentura/features/beacon/data/gql/_g/beacon_promotion_source.req.gql.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_denial_code.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

const _fetchPolicies = {
  OperationType.query: FetchPolicy.NoCache,
  OperationType.mutation: FetchPolicy.NoCache,
};

void main() {
  group('BeaconHierarchyRepository mapping', () {
    test('mapCapabilities success with and without a denial code', () async {
      final client = Client(
        link: _FakeLink(
          const Response(
            data: {
              '__typename': 'query_root',
              'beaconHierarchyCapabilities': {
                '__typename': 'v2_BeaconHierarchyCapabilities',
                'canListChildren': true,
                'canCreateChild': false,
                'denialCode': 'notAdmitted',
              },
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );
      final response = await client
          .request(
            GBeaconHierarchyCapabilitiesReq((b) => b.vars.beaconId = 'B1'),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link);
      final capabilities = BeaconHierarchyRepository.mapCapabilities(
        response.dataOrThrow(label: 'test').beaconHierarchyCapabilities,
      );
      expect(capabilities.canListChildren, isTrue);
      expect(capabilities.canCreateChild, isFalse);
      expect(capabilities.denialCode, BeaconHierarchyDenialCode.notAdmitted);
    });

    test('mapChildrenPage maps summaries, owner, cursor', () async {
      final client = Client(
        link: _FakeLink(
          const Response(
            data: {
              '__typename': 'query_root',
              'beaconChildren': {
                '__typename': 'v2_BeaconHierarchyPage',
                'nextCursor': 'opaque-cursor',
                'summaries': [
                  {
                    '__typename': 'v2_BeaconHierarchySummary',
                    'beaconId': 'Bchild0000001',
                    'title': 'Fix the fence',
                    'status': 0,
                    'publishedAt': '2026-08-01T00:00:00.000Z',
                    'isTombstone': false,
                    'owner': {
                      '__typename': 'v2_BeaconHierarchyOwnerSummary',
                      'id': 'Uowner0000001',
                      'displayName': 'Owner One',
                      'avatarImageId': null,
                    },
                  },
                  {
                    '__typename': 'v2_BeaconHierarchySummary',
                    'beaconId': 'Bchild0000002',
                    'title': null,
                    'status': 2,
                    'publishedAt': '2026-08-02T00:00:00.000Z',
                    'isTombstone': true,
                    'owner': null,
                  },
                ],
              },
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );
      final response = await client
          .request(
            GBeaconChildrenReq(
              (b) => b.vars
                ..parentBeaconId = 'B1'
                ..group = 'active',
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link);
      final page = BeaconHierarchyRepository.mapChildrenPage(
        response.dataOrThrow(label: 'test').beaconChildren,
      );
      expect(page.nextCursor, 'opaque-cursor');
      expect(page.summaries, hasLength(2));
      expect(page.summaries.first.owner?.displayName, 'Owner One');
      expect(page.summaries.first.status, BeaconStatus.open);
      expect(page.summaries.last.owner, isNull);
      expect(page.summaries.last.isTombstone, isTrue);
      expect(page.summaries.last.title, isNull);
    });

    test('mapParentReference success for each state', () async {
      final client = Client(
        link: _FakeLink(
          const Response(
            data: {
              '__typename': 'query_root',
              'beaconParentReference': {
                '__typename': 'v2_BeaconParentReference',
                'state': 'available',
                'beaconId': 'Bparent000001',
                'title': 'Parent request',
              },
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );
      final response = await client
          .request(GBeaconParentReferenceReq((b) => b.vars.beaconId = 'B1'))
          .firstWhere((e) => e.dataSource == DataSource.Link);
      final reference = BeaconHierarchyRepository.mapParentReference(
        response.dataOrThrow(label: 'test').beaconParentReference,
      );
      expect(reference.state, BeaconParentReferenceState.available);
      expect(reference.beaconId, 'Bparent000001');
      expect(reference.title, 'Parent request');
    });

    test('mapPromotionSource success', () async {
      final client = Client(
        link: _FakeLink(
          const Response(
            data: {
              '__typename': 'query_root',
              'beaconPromotionSource': {
                '__typename': 'v2_BeaconPromotionSource',
                'sourceBeaconId': 'B1',
                'sourceMessageId': 'R1',
                'textPreview': 'Can someone help with the fence?',
                'author': {
                  '__typename': 'v2_BeaconHierarchyOwnerSummary',
                  'id': 'Uauthor0000001',
                  'displayName': 'Author One',
                  'avatarImageId': 'Iavatar000001',
                },
              },
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: _fetchPolicies,
      );
      final response = await client
          .request(
            GBeaconPromotionSourceReq(
              (b) => b.vars
                ..parentBeaconId = 'B1'
                ..sourceMessageId = 'R1',
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link);
      final source = BeaconHierarchyRepository.mapPromotionSource(
        response.dataOrThrow(label: 'test').beaconPromotionSource,
      );
      expect(source.sourceBeaconId, 'B1');
      expect(source.sourceMessageId, 'R1');
      expect(source.textPreview, 'Can someone help with the fence?');
      expect(source.author.displayName, 'Author One');
    });

    test('mapChildCreateOutcome success for created/replayed/alreadyPromoted', () async {
      for (final entry in {
        'created': BeaconChildCommandOutcome.created,
        'replayed': BeaconChildCommandOutcome.replayed,
        'alreadyPromoted': BeaconChildCommandOutcome.alreadyPromoted,
      }.entries) {
        final client = Client(
          link: _FakeLink(
            Response(
              data: {
                '__typename': 'mutation_root',
                'beaconChildCreate': {
                  '__typename': 'v2_BeaconChildCreateResult',
                  'outcome': entry.key,
                  'beaconId': entry.key == 'alreadyPromoted' ? null : 'Bnew0000001',
                  'beacon': entry.key == 'alreadyPromoted'
                      ? null
                      : {'__typename': 'v2_Beacon', 'id': 'Bnew0000001'},
                },
              },
              response: const {},
            ),
          ),
          defaultFetchPolicies: _fetchPolicies,
        );
        final response = await client
            .request(
              GBeaconChildCreateReq(
                (b) => b.vars
                  ..parentBeaconId = 'B1'
                  ..clientCommandId = 'cmd-1'
                  ..title = 'Fix the fence',
              ),
            )
            .firstWhere((e) => e.dataSource == DataSource.Link);
        final outcome = BeaconHierarchyRepository.mapChildCreateOutcome(
          response.dataOrThrow(label: 'test').beaconChildCreate,
        );
        expect(outcome.outcome, entry.value, reason: entry.key);
        if (entry.key == 'alreadyPromoted') {
          expect(outcome.beaconId, isNull, reason: entry.key);
        } else {
          expect(outcome.beaconId, 'Bnew0000001', reason: entry.key);
        }
      }
    });
  });

  group('throwIfBeaconHierarchyError', () {
    test('translates every nested-request error code to its typed exception', () {
      expect(
        () => throwIfBeaconHierarchyError(1309, null),
        throwsA(isA<BeaconChildCreateForbiddenException>()),
      );
      expect(
        () => throwIfBeaconHierarchyError(1310, null),
        throwsA(isA<BeaconParentNotCoordinatableException>()),
      );
      expect(
        () => throwIfBeaconHierarchyError(1311, null),
        throwsA(isA<BeaconPromotionSourceInvalidException>()),
      );
      expect(
        () => throwIfBeaconHierarchyError(1313, null),
        throwsA(isA<BeaconChildCommandConflictException>()),
      );
      expect(
        () => throwIfBeaconHierarchyError(1314, null),
        throwsA(isA<BeaconChildCommandGoneException>()),
      );
      expect(
        () => throwIfBeaconHierarchyError(1315, null),
        throwsA(isA<DiscussionScopeDisabledException>()),
      );
      expect(
        () => throwIfBeaconHierarchyError(1316, null),
        throwsA(isA<CoordinationKindDisabledException>()),
      );
      expect(
        () => throwIfBeaconHierarchyError(1317, null),
        throwsA(isA<BeaconHierarchyCursorInvalidException>()),
      );
    });

    test(
      'BeaconSourceAlreadyPromoted carries beaconId only when the extension is present',
      () {
        expect(
          () => throwIfBeaconHierarchyError(1312, {'beaconId': 'Bexisting001'}),
          throwsA(
            isA<BeaconSourceAlreadyPromotedException>().having(
              (e) => e.existingChildBeaconId,
              'existingChildBeaconId',
              'Bexisting001',
            ),
          ),
        );
        expect(
          () => throwIfBeaconHierarchyError(1312, null),
          throwsA(
            isA<BeaconSourceAlreadyPromotedException>().having(
              (e) => e.existingChildBeaconId,
              'existingChildBeaconId',
              isNull,
            ),
          ),
        );
      },
    );

    test('an unrecognized code does not throw', () {
      expect(() => throwIfBeaconHierarchyError(1301, null), returnsNormally);
      expect(() => throwIfBeaconHierarchyError(null, null), returnsNormally);
    });
  });
}
