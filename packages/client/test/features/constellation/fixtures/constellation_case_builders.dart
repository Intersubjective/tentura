import 'dart:async';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/constellation/data/repository/constellation_mutual_trust_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_trust_chain_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_tag_magnet.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_trust_chain_person.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_hide_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_mutual_trust_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_tag_magnet_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_targeted_read_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_trust_chain_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_hide_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_mutual_trust_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_trust_chain_case.dart';

ConstellationAnchorCase buildTestAnchorCase() => ConstellationAnchorCase();

ConstellationFieldHideCase buildTestFieldHideCase(
  ConstellationFieldHidePort port,
  ConstellationFieldStoreCase store,
) => ConstellationFieldHideCase(port, store, _EmptyTargetedReads());

ConstellationTagMagnetCase buildTestSavedTagMagnetCase(
  String tagId,
  RealtimeSyncCase realtime,
) => ConstellationTagMagnetCase(_SavedMagnet(tagId), realtime);

ConstellationMutualTrustCase buildTestMutualTrustCase(
  Map<String, Set<String>> answers,
) => ConstellationMutualTrustCase(_MutualTrustAnswers(answers));

ConstellationMutualTrustCase buildWireMutualTrustCase(
  RemoteApiService remote,
) => ConstellationMutualTrustCase(ConstellationMutualTrustRepository(remote));

ConstellationTrustChainCase buildWireTrustChainCase(
  RemoteApiService remote,
) => ConstellationTrustChainCase(ConstellationTrustChainRepository(remote));

ConstellationTrustChainCase buildTestControlledTrustChainCase(
  ControlledTrustChainPort port,
) => ConstellationTrustChainCase(port);

/// Answers each person's fetch with a completer the test settles.
final class ControlledTrustChainPort implements ConstellationTrustChainPort {
  final List<String> fetched = [];
  final Map<String, Completer<List<ConstellationTrustChainPerson>>> pending =
      {};

  @override
  Future<List<ConstellationTrustChainPerson>> fetchTrustChain(
    String personId,
  ) {
    fetched.add(personId);
    return (pending[personId] =
            Completer<List<ConstellationTrustChainPerson>>())
        .future;
  }

  void answer(String personId, List<ConstellationTrustChainPerson> chain) =>
      pending[personId]!.complete(chain);
}

final class _EmptyTargetedReads implements ConstellationTargetedReadPort {
  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async => const [];

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async => const [];
}

final class _SavedMagnet implements ConstellationTagMagnetRepositoryPort {
  _SavedMagnet(this.tagId);

  final String tagId;

  @override
  Future<List<ConstellationTagMagnet>> list() async => [
    ConstellationTagMagnet(
      tagId: tagId,
      xUnits: 2.5,
      yUnits: 1.5,
      revision: 1,
    ),
  ];

  @override
  Future<ConstellationTagMagnet> upsert({
    required String tagId,
    required double xUnits,
    required double yUnits,
    required String clientOpId,
  }) => throw UnimplementedError();

  @override
  Future<void> remove({
    required String tagId,
    required String clientOpId,
  }) => throw UnimplementedError();
}

final class _MutualTrustAnswers implements ConstellationMutualTrustPort {
  _MutualTrustAnswers(this.answers);

  final Map<String, Set<String>> answers;

  @override
  Future<Set<String>> fetchMutualTrust(String personId) async =>
      answers[personId] ?? const {};
}
