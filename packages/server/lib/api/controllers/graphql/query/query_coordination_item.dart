import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryCoordinationItem extends GqlNodeBase {
  QueryCoordinationItem({
    CoordinationItemRepositoryPort? itemRepository,
  }) : _itemRepository =
           itemRepository ?? GetIt.I<CoordinationItemRepositoryPort>();

  final CoordinationItemRepositoryPort _itemRepository;

  final _beaconId = InputFieldString(fieldName: 'beaconId');
  final _itemId = InputFieldString(fieldName: 'itemId');
  final _statusFilter = InputFieldInt(fieldName: 'status');
  final _kindFilter = InputFieldInt(fieldName: 'kind');
  final _acceptedById = InputFieldString(fieldName: 'acceptedById');
  final _targetPersonId = InputFieldString(fieldName: 'targetPersonId');
  final _linkedParentItemId = InputFieldString(fieldName: 'linkedParentItemId');
  final _rootOnly = InputFieldBool(fieldName: 'rootOnly');
  final _limit = InputFieldInt(fieldName: 'limit');
  final _before = InputFieldString(fieldName: 'before');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        coordinationItemsByBeacon,
        coordinationItemMessages,
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
          getCredentials(args);
          final beaconId = _beaconId.fromArgsNonNullable(args);
          final status = _statusFilter.fromArgs(args);
          final kind = _kindFilter.fromArgs(args);
          final items = await _itemRepository.listByBeacon(
            beaconId,
            status: status,
            kind: kind,
            acceptedById: _acceptedById.fromArgs(args),
            targetPersonId: _targetPersonId.fromArgs(args),
            linkedParentItemId: _linkedParentItemId.fromArgs(args),
            rootOnly: _rootOnly.fromArgs(args) ?? false,
          );
          return items.map(_coordinationItemToMap).toList();
        },
      );

  GraphQLObjectField<dynamic, dynamic> get coordinationItemMessages =>
      GraphQLObjectField(
        'coordinationItemMessages',
        GraphQLListType(
          gqlTypeCoordinationItemMessageRow.nonNullable(),
        ),
        arguments: [
          _itemId.field,
          _limit.fieldNullable,
          _before.fieldNullable,
        ],
        resolve: (_, args) async {
          getCredentials(args);
          final itemId = _itemId.fromArgsNonNullable(args);
          final limit = _limit.fromArgs(args);
          final before = _before.fromArgs(args);
          final messages = await _itemRepository.listMessages(
            itemId,
            limit: limit,
            before: before,
          );
          return messages.map(_coordinationItemMessageToMap).toList();
        },
      );
}

Map<String, Object?> _coordinationItemToMap(CoordinationItem item) => {
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
      'createdAt': item.createdAt.dateTime.toIso8601String(),
      'updatedAt': item.updatedAt.dateTime.toIso8601String(),
      'resolvedAt': item.resolvedAt?.dateTime.toIso8601String(),
      'cancelledAt': item.cancelledAt?.dateTime.toIso8601String(),
    };

Map<String, Object?> _coordinationItemMessageToMap(
  CoordinationItemMessage msg,
) =>
    {
      'id': msg.id,
      'itemId': msg.itemId,
      'beaconId': msg.beaconId,
      'senderId': msg.senderId,
      'body': msg.body,
      'createdAt': msg.createdAt.dateTime.toIso8601String(),
      'editedAt': msg.editedAt?.dateTime.toIso8601String(),
    };
