import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/coordination_item/coordination_responsibility_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/coordination_room_access.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryCoordinationItem extends GqlNodeBase {
  QueryCoordinationItem({
    CoordinationItemRepositoryPort? itemRepository,
    BeaconRoomRepositoryPort? roomRepository,
    CoordinationResponsibilityCase? responsibilityCase,
  })  : _itemRepository =
            itemRepository ?? GetIt.I<CoordinationItemRepositoryPort>(),
        _room = roomRepository ?? GetIt.I<BeaconRoomRepositoryPort>(),
        _responsibilityCase =
            responsibilityCase ?? GetIt.I<CoordinationResponsibilityCase>();

  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepositoryPort _room;
  final CoordinationResponsibilityCase _responsibilityCase;

  final _beaconId = InputFieldString(fieldName: 'beaconId');
  final _statusFilter = InputFieldInt(fieldName: 'status');
  final _kindFilter = InputFieldInt(fieldName: 'kind');
  final _acceptedById = InputFieldString(fieldName: 'acceptedById');
  final _targetPersonId = InputFieldString(fieldName: 'targetPersonId');
  final _linkedParentItemId = InputFieldString(fieldName: 'linkedParentItemId');
  final _rootOnly = InputFieldBool(fieldName: 'rootOnly');
  final _beaconIds = InputFieldStringList(fieldName: 'beaconIds');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        coordinationItemsByBeacon,
        myWorkCoordinationItemActivity,
        coordinationResponsibilityBatch,
        coordinationMyResponsibilityItems,
      ];

  GraphQLObjectField<dynamic, dynamic> get coordinationItemsByBeacon =>
      GraphQLObjectField(
        'coordinationItemsByBeacon',
        GraphQLListType(gqlTypeCoordinationItemRow.nonNullable()),
        arguments: [
          _beaconId.field,
          _statusFilter.fieldNullable,
          _kindFilter.fieldNullable,
          _acceptedById.fieldNullable,
          _targetPersonId.fieldNullable,
          _linkedParentItemId.fieldNullable,
          _rootOnly.fieldNullable,
        ],
        resolve: (_, args) async {
          final viewerUserId = getCredentials(args).sub;
          final beaconId = _beaconId.fromArgsNonNullable(args);
          await ensureCanCoordinateOnBeacon(
            room: _room,
            beaconId: beaconId,
            userId: viewerUserId,
          );
          final status = _statusFilter.fromArgs(args);
          final kind = _kindFilter.fromArgs(args);
          final items = await _itemRepository.listByBeacon(
            beaconId,
            viewerUserId: viewerUserId,
            status: status,
            kind: kind,
            acceptedById: _acceptedById.fromArgs(args),
            targetPersonId: _targetPersonId.fromArgs(args),
            linkedParentItemId: _linkedParentItemId.fromArgs(args),
            rootOnly: _rootOnly.fromArgs(args) ?? false,
          );
          return items.map(coordinationItemWithCountsToMap).toList();
        },
      );

  GraphQLObjectField<dynamic, dynamic> get myWorkCoordinationItemActivity =>
      GraphQLObjectField(
        'myWorkCoordinationItemActivity',
        GraphQLListType(
          gqlTypeMyWorkBeaconCoordinationActivityRow.nonNullable(),
        ),
        arguments: [_beaconIds.field],
        resolve: (_, args) async {
          final viewerUserId = getCredentials(args).sub;
          final beaconIds = _beaconIds.fromArgsNonNullable(args);
          final byBeacon = await _itemRepository
              .lastCoordinationItemMessageAtByBeaconIds(
            beaconIds: beaconIds,
            viewerUserId: viewerUserId,
          );
          return beaconIds
              .map(
                (id) => {
                  'beaconId': id,
                  'lastCoordinationItemMessageAt':
                      byBeacon[id]?.toUtc().toIso8601String(),
                },
              )
              .toList();
        },
      );

  GraphQLObjectField<dynamic, dynamic> get coordinationResponsibilityBatch =>
      GraphQLObjectField(
        'coordinationResponsibilityBatch',
        GraphQLListType(gqlTypeCoordinationResponsibilityBatchRow.nonNullable()),
        arguments: [_beaconIds.field],
        resolve: (_, args) async {
          final viewerUserId = getCredentials(args).sub;
          final beaconIds = _beaconIds.fromArgsNonNullable(args);
          final rows = await _responsibilityCase.batch(
            viewerUserId: viewerUserId,
            beaconIds: beaconIds,
          );
          return rows
              .map(
                (r) => {
                  'beaconId': r.beaconId,
                  'askOpen': r.askOpen,
                  'askNew': r.askNew,
                  'promiseOpen': r.promiseOpen,
                  'promiseNew': r.promiseNew,
                  'blockerOpen': r.blockerOpen,
                  'blockerNew': r.blockerNew,
                  'reviewOpen': r.reviewOpen,
                  'reviewNew': r.reviewNew,
                  'othersOpenCount': r.othersOpenCount,
                },
              )
              .toList();
        },
      );

  GraphQLObjectField<dynamic, dynamic> get coordinationMyResponsibilityItems =>
      GraphQLObjectField(
        'coordinationMyResponsibilityItems',
        GraphQLListType(gqlTypeCoordinationItemRow.nonNullable()),
        arguments: [_beaconId.field],
        resolve: (_, args) async {
          final viewerUserId = getCredentials(args).sub;
          final beaconId = _beaconId.fromArgsNonNullable(args);
          final items = await _responsibilityCase.myItems(
            viewerUserId: viewerUserId,
            beaconId: beaconId,
          );
          return items.map(coordinationItemWithCountsToMap).toList();
        },
      );
}

Map<String, Object?> coordinationItemWithCountsToMap(
  CoordinationItemWithCounts row,
) {
  final item = row.item;
  return {
    'id': item.id,
    'beaconId': item.beaconId,
    'kind': item.kind,
    'status': item.status,
    'title': item.title,
    'body': item.body,
    'creatorId': item.creatorId,
    'targetPersonId': item.targetPersonId,
    'acceptedById': item.acceptedById,
    'targetItemId': item.targetItemId,
    'targetMessageId': item.targetMessageId,
    'linkedMessageId': item.linkedMessageId,
    'linkedParentItemId': item.linkedParentItemId,
    'ordering': item.ordering,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
    'resolvedAt': item.resolvedAt?.toIso8601String(),
    'cancelledAt': item.cancelledAt?.toIso8601String(),
    'staleAt': item.staleAt?.toIso8601String(),
    'lastRemindedAt': item.lastRemindedAt?.toIso8601String(),
    'staleAfterDays': item.staleAfterDays,
    'source': item.source,
    'published': item.published,
    'messageCount': row.messageCount,
    'unreadCount': row.unreadCount,
    'lastSeenAt': row.lastSeenAt?.toUtc().toIso8601String(),
  };
}
