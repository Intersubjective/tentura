import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';

import '../gql/_g/capability_private_label_set.req.gql.dart';
import '../gql/_g/my_private_labels_for_user.req.gql.dart';
import '../gql/_g/person_capability_cues_fetch.req.gql.dart';

@LazySingleton(
  as: CapabilityRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class CapabilityRepository implements CapabilityRepositoryPort {
  CapabilityRepository(
    this._remoteApiService,
    InvalidationService invalidationService,
  ) {
    _capabilityInvalidationSub =
        invalidationService.capabilityInvalidations.listen(
      (_) => _changesController.add(null),
    );
  }

  final RemoteApiService _remoteApiService;

  late final StreamSubscription<String> _capabilityInvalidationSub;

  final _changesController = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changesController.stream;

  @override
  @disposeMethod
  Future<void> dispose() async {
    await _capabilityInvalidationSub.cancel();
    await _changesController.close();
  }

  @override
  Future<List<String>> fetchMyPrivateLabelsForUser(String subjectId) =>
      _remoteApiService
          .request(
            GMyPrivateLabelsForUserReq(
              (r) => r..vars.subjectUserId = subjectId,
            ),
          )
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => r
                .dataOrThrow(label: _label)
                .myPrivateLabelsForUser
                .toList(),
          );

  @override
  Future<void> setPrivateLabels({
    required String subjectId,
    required List<String> slugs,
  }) => _remoteApiService
      .request(
        GCapabilityPrivateLabelSetReq(
          (r) => r
            ..vars.subjectUserId = subjectId
            ..vars.slugs.addAll(slugs),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) => _remoteApiService
      .request(
        GPersonCapabilityCuesReq(
          (r) => r..vars.subjectUserId = subjectId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).personCapabilityCues)
      .then((p) {
        return PersonCapabilityCues(
          privateLabels: p.privateLabels?.toList() ?? [],
          forwardReasonsByMe: p.forwardReasonsByMe
                  ?.map(
                    (e) => TagCount(
                      slug: e.slug,
                      count: e.count,
                      lastSeenAt: e.lastSeenAt,
                    ),
                  )
                  .toList() ??
              [],
          commitRoles: p.commitRoles
                  ?.map(
                    (e) => TagBeaconRef(
                      slug: e.slug,
                      beaconId: e.beaconId,
                      beaconTitle: e.beaconTitle,
                      createdAt: e.createdAt,
                    ),
                  )
                  .toList() ??
              [],
          closeAckByMe: p.closeAckByMe
                  ?.map(
                    (e) => TagBeaconRef(
                      slug: e.slug,
                      beaconId: e.beaconId,
                      beaconTitle: e.beaconTitle,
                      createdAt: e.createdAt,
                    ),
                  )
                  .toList() ??
              [],
          closeAckAboutMe: p.closeAckAboutMe
                  ?.map(
                    (e) => TagBeaconRef(
                      slug: e.slug,
                      beaconId: e.beaconId,
                      beaconTitle: e.beaconTitle,
                      createdAt: e.createdAt,
                    ),
                  )
                  .toList() ??
              [],
        );
      });

  static const _label = 'Capability';
}
