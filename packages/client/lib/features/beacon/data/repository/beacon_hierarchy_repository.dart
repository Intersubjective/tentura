import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_denial_code.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_promotion_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';

import '../gql/_g/beacon_child_create.data.gql.dart';
import '../gql/_g/beacon_child_create.req.gql.dart';
import '../gql/_g/beacon_children.data.gql.dart';
import '../gql/_g/beacon_children.req.gql.dart';
import '../gql/_g/beacon_hierarchy_capabilities.data.gql.dart';
import '../gql/_g/beacon_hierarchy_capabilities.req.gql.dart';
import '../gql/_g/beacon_parent_reference.data.gql.dart';
import '../gql/_g/beacon_parent_reference.req.gql.dart';
import '../gql/_g/beacon_promotion_source.data.gql.dart';
import '../gql/_g/beacon_promotion_source.req.gql.dart';

String? _scheduleDateTimeToIso(DateTime? dateTime) =>
    dateTime?.toUtc().toIso8601String();

@Singleton(as: BeaconHierarchyRepositoryPort, env: [Environment.dev, Environment.prod])
class BeaconHierarchyRepository implements BeaconHierarchyRepositoryPort {
  BeaconHierarchyRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'BeaconHierarchy';

  @override
  Future<BeaconHierarchyCapabilities> fetchCapabilities({
    required String beaconId,
  }) async {
    final data = await _remoteApiService
        .request(GBeaconHierarchyCapabilitiesReq((b) => b.vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconHierarchyCapabilities);
    return mapCapabilities(data);
  }

  @visibleForTesting
  static BeaconHierarchyCapabilities mapCapabilities(
    GBeaconHierarchyCapabilitiesData_beaconHierarchyCapabilities data,
  ) => BeaconHierarchyCapabilities(
    canListChildren: data.canListChildren,
    canCreateChild: data.canCreateChild,
    denialCode: data.denialCode == null
        ? null
        : BeaconHierarchyDenialCode.values.byName(data.denialCode!),
  );

  @override
  Future<BeaconHierarchyPage> fetchChildren({
    required String parentBeaconId,
    required BeaconHierarchyChildGroup group,
    int first = 20,
    String? after,
  }) async {
    final data = await _remoteApiService
        .request(
          GBeaconChildrenReq((b) {
            b.vars
              ..parentBeaconId = parentBeaconId
              ..group = group.name
              ..first = first
              ..after = after;
          }),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconChildren);
    return mapChildrenPage(data);
  }

  @visibleForTesting
  static BeaconHierarchyPage mapChildrenPage(
    GBeaconChildrenData_beaconChildren data,
  ) => BeaconHierarchyPage(
    nextCursor: data.nextCursor,
    summaries: data.summaries.map(mapChildSummary).toList(),
  );

  @visibleForTesting
  static BeaconHierarchySummary mapChildSummary(
    GBeaconChildrenData_beaconChildren_summaries row,
  ) => BeaconHierarchySummary(
    beaconId: row.beaconId,
    title: row.title,
    owner: row.owner == null
        ? null
        : BeaconHierarchyOwnerSummary(
            id: row.owner!.id,
            displayName: row.owner!.displayName,
            avatarImageId: row.owner!.avatarImageId,
          ),
    status: BeaconStatus.fromSmallint(row.status),
    publishedAt: DateTime.parse(row.publishedAt),
    isTombstone: row.isTombstone,
  );

  @override
  Future<BeaconParentReference> fetchParentReference({
    required String beaconId,
  }) async {
    final data = await _remoteApiService
        .request(GBeaconParentReferenceReq((b) => b.vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconParentReference);
    return mapParentReference(data);
  }

  @visibleForTesting
  static BeaconParentReference mapParentReference(
    GBeaconParentReferenceData_beaconParentReference data,
  ) => BeaconParentReference(
    state: BeaconParentReferenceState.values.byName(data.state),
    beaconId: data.beaconId,
    title: data.title,
  );

  @override
  Future<BeaconPromotionSource> fetchPromotionSource({
    required String parentBeaconId,
    required String sourceMessageId,
  }) async {
    final data = await _remoteApiService
        .request(
          GBeaconPromotionSourceReq((b) {
            b.vars
              ..parentBeaconId = parentBeaconId
              ..sourceMessageId = sourceMessageId;
          }),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconPromotionSource);
    return mapPromotionSource(data);
  }

  @visibleForTesting
  static BeaconPromotionSource mapPromotionSource(
    GBeaconPromotionSourceData_beaconPromotionSource data,
  ) => BeaconPromotionSource(
    sourceBeaconId: data.sourceBeaconId,
    sourceMessageId: data.sourceMessageId,
    textPreview: data.textPreview,
    author: BeaconHierarchyOwnerSummary(
      id: data.author.id,
      displayName: data.author.displayName,
      avatarImageId: data.author.avatarImageId,
    ),
  );

  @override
  Future<BeaconChildCreateOutcome> createChild({
    required String parentBeaconId,
    String? sourceMessageId,
    required String clientCommandId,
    required String title,
    String? description,
    String? context,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    String? addressLabel,
    bool draft = false,
  }) async {
    final data = await _remoteApiService
        .request(
          GBeaconChildCreateReq((b) {
            b.vars
              ..parentBeaconId = parentBeaconId
              ..sourceMessageId = sourceMessageId
              ..clientCommandId = clientCommandId
              ..title = title
              ..description = description ?? ''
              ..context = context
              ..coordinates = coordinates == null
                  ? null
                  : (Gv2_CoordinatesBuilder()
                      ..lat = coordinates.lat
                      ..long = coordinates.long)
              ..startAt = _scheduleDateTimeToIso(startAt)
              ..endAt = _scheduleDateTimeToIso(endAt)
              ..tags = tags
              ..needs = needs
              ..primaryNeedSlug = primaryNeedSlug
              ..addressLabel = addressLabel
              ..draft = draft;
          }),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconChildCreate);
    return mapChildCreateOutcome(data);
  }

  @visibleForTesting
  static BeaconChildCreateOutcome mapChildCreateOutcome(
    GBeaconChildCreateData_beaconChildCreate data,
  ) => BeaconChildCreateOutcome(
    outcome: BeaconChildCommandOutcome.values.byName(data.outcome),
    beaconId: data.beaconId,
  );
}
