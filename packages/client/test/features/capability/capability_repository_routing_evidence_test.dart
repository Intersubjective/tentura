import 'package:ferry/ferry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/domain/capability/projection_tier.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/features/capability/data/gql/_g/forward_context_fetch.data.gql.dart';
import 'package:tentura/features/capability/data/gql/_g/forward_context_fetch.req.gql.dart';
import 'package:tentura/features/capability/data/gql/_g/set_routing_mute.data.gql.dart';
import 'package:tentura/features/capability/data/gql/_g/set_routing_mute.req.gql.dart';
import 'package:tentura/features/capability/data/gql/_g/set_routing_mute.var.gql.dart';
import 'package:tentura/features/capability/data/gql/_g/subjective_tags_fetch.data.gql.dart';
import 'package:tentura/features/capability/data/gql/_g/subjective_tags_fetch.req.gql.dart';
import 'package:tentura/features/capability/data/repository/capability_repository.dart';

void main() {
  group('CapabilityRepository subjective help-tag evidence', () {
    test('fetchSubjectiveTags maps populated response to domain entities', () async {
      final remote = _FixtureRemoteClient();
      final repository = _repository(remote);
      remote.subjectiveTagsData = GSubjectiveTagsData.fromJson({
        '__typename': 'query_root',
        'subjectiveTags': [
          {
            '__typename': 'v2_TagProjection',
            'subjectUserId': 'Usubject000001',
            'tagSlug': 'transport',
            'tier': 'networkOutcome',
          },
        ],
      });
      expect(remote.subjectiveTagsData, isNotNull);

      final rows = await repository.fetchSubjectiveTags('Usubject000001');

      expect(rows, hasLength(1));
      expect(rows.single.subjectUserId, 'Usubject000001');
      expect(rows.single.tagSlug, 'transport');
      expect(rows.single.tier, ProjectionTier.networkOutcome);
    });

    test('fetchSubjectiveTags maps null server list to empty list', () async {
      final remote = _FixtureRemoteClient();
      final repository = _repository(remote);
      remote.subjectiveTagsData = GSubjectiveTagsData.fromJson({
        '__typename': 'query_root',
        'subjectiveTags': null,
      });
      expect(remote.subjectiveTagsData, isNotNull);

      expect(await repository.fetchSubjectiveTags('Usubject000001'), isEmpty);
    });

    test('fetchForwardContext maps null outer list to empty list', () async {
      final remote = _FixtureRemoteClient();
      final repository = _repository(remote);
      remote.forwardContextData = GForwardContextData.fromJson({
        '__typename': 'query_root',
        'forwardContext': null,
      });
      expect(remote.forwardContextData, isNotNull);

      expect(
        await repository.fetchForwardContext(beaconId: 'Bbeacon0000001'),
        isEmpty,
      );
    });

    test('setRoutingMute sends variables and accepts true response', () async {
      final remote = _FixtureRemoteClient();
      final repository = _repository(remote);
      remote.setRoutingMuteData = GSetRoutingMuteData.fromJson({
        '__typename': 'mutation_root',
        'setRoutingMute': true,
      });
      expect(remote.setRoutingMuteData, isNotNull);

      await repository.setRoutingMute(slug: 'transport', muted: true);

      expect(remote.lastSetRoutingMuteVars?.slug, 'transport');
      expect(remote.lastSetRoutingMuteVars?.muted, isTrue);
    });
  });
}

CapabilityRepository _repository(_FixtureRemoteClient remote) =>
    CapabilityRepository(remote, _NoopRealtimeSync());

final class _NoopRealtimeSync implements RealtimeSyncPort {
  @override
  Stream<RealtimeCatchUp> get catchUps => const Stream.empty();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      const Stream.empty();

  @override
  Stream<RealtimeEntityChange> get entityChanges => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}
}

final class _FixtureRemoteClient implements RemoteRequestClient {
  GSubjectiveTagsData? subjectiveTagsData;
  GForwardContextData? forwardContextData;
  GSetRoutingMuteData? setRoutingMuteData;
  GSetRoutingMuteVars? lastSetRoutingMuteVars;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    if (request is GSubjectiveTagsReq) {
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: subjectiveTagsData as TData,
        ),
      );
    }
    if (request is GForwardContextReq) {
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: forwardContextData as TData,
        ),
      );
    }
    if (request is GSetRoutingMuteReq) {
      lastSetRoutingMuteVars = (request as GSetRoutingMuteReq).vars;
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: setRoutingMuteData as TData,
        ),
      );
    }
    throw UnsupportedError('Unexpected operation: $request');
  }
}
