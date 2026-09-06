import 'package:tentura_server/domain/entity/coordination_item_record.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_plan_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/add_plan_step_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_plan_step_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_coordination_item_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/remind_coordination_item_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/coordination_responsibility_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationCoordinationItem extends GqlNodeBase {
  MutationCoordinationItem({
    UpdatePlanCase? updatePlanCase,
    AddPlanStepCase? addPlanStepCase,
    ResolvePlanStepCase? resolvePlanStepCase,
    UpdateCoordinationItemCase? updateCoordinationItemCase,
    RemindCoordinationItemCase? remindCoordinationItemCase,
    CoordinationResponsibilityCase? responsibilityCase,
  }) : _updatePlanCase = updatePlanCase ?? GetIt.I<UpdatePlanCase>(),
       _addPlanStepCase = addPlanStepCase ?? GetIt.I<AddPlanStepCase>(),
       _resolvePlanStepCase =
           resolvePlanStepCase ?? GetIt.I<ResolvePlanStepCase>(),
       _updateCoordinationItemCase =
           updateCoordinationItemCase ?? GetIt.I<UpdateCoordinationItemCase>(),
       _remindCoordinationItemCase =
           remindCoordinationItemCase ?? GetIt.I<RemindCoordinationItemCase>(),
       _responsibilityCase =
           responsibilityCase ?? GetIt.I<CoordinationResponsibilityCase>();

  final UpdatePlanCase _updatePlanCase;
  final AddPlanStepCase _addPlanStepCase;
  final ResolvePlanStepCase _resolvePlanStepCase;
  final UpdateCoordinationItemCase _updateCoordinationItemCase;
  final RemindCoordinationItemCase _remindCoordinationItemCase;
  final CoordinationResponsibilityCase _responsibilityCase;

  final _beaconId = InputFieldString(fieldName: 'beaconId');
  final _parentItemId = InputFieldString(fieldName: 'parentItemId');
  final _title = InputFieldString(fieldName: 'title');
  final _body = InputFieldString(fieldName: 'body');
  final _itemId = InputFieldString(fieldName: 'itemId');
  final _linkedMessageId = InputFieldString(fieldName: 'linkedMessageId');
  final _targetPersonId = InputFieldString(fieldName: 'targetPersonId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        updateCoordinationPlan,
        addPlanStep,
        resolvePlanStep,
        updateCoordinationItem,
        remindCoordinationItem,
        markBeaconItemsSeen,
      ];

  GraphQLObjectField<dynamic, dynamic> get updateCoordinationItem =>
      GraphQLObjectField(
        'updateCoordinationItem',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _title.field,
          _body.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _updateCoordinationItemCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get updateCoordinationPlan =>
      GraphQLObjectField(
        'updateCoordinationPlan',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _body.fieldNullable,
          _targetPersonId.fieldNullable,
          _linkedMessageId.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _updatePlanCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            targetPersonId: _targetPersonId.fromArgs(args),
            linkedMessageId: _linkedMessageId.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get addPlanStep => GraphQLObjectField(
        'addPlanStep',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _parentItemId.field,
          _title.field,
          _body.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _addPlanStepCase.call(
            userId: userId,
            parentItemId: _parentItemId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get resolvePlanStep =>
      GraphQLObjectField(
        'resolvePlanStep',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _resolvePlanStepCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get remindCoordinationItem =>
      GraphQLObjectField(
        'remindCoordinationItem',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [_itemId.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _remindCoordinationItemCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get markBeaconItemsSeen =>
      GraphQLObjectField(
        'markBeaconItemsSeen',
        gqlTypeBeaconItemsSeenResult.nonNullable(),
        arguments: [_beaconId.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final beaconId = _beaconId.fromArgsNonNullable(args);
          final seenAt = await _responsibilityCase.markSeen(
            viewerUserId: userId,
            beaconId: beaconId,
          );
          return {
            'beaconId': beaconId,
            'seenAt': seenAt.toUtc().toIso8601String(),
          };
        },
      );
}

Map<String, Object?> _coordinationItemToMap(CoordinationItemRecord item) => {
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
      // `CoordinationItemRow` declares messageCount/unreadCount as non-nullable,
      // but a mutation returns a bare CoordinationItem with no thread counts.
      // Emit zero defaults to satisfy the schema; clients read accurate counts
      // from coordinationItemsByBeacon. lastSeenAt is nullable, so null is fine.
      'messageCount': 0,
      'unreadCount': 0,
      'lastSeenAt': null,
    };
