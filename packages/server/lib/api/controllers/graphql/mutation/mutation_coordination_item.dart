import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/use_case/coordination_item/mark_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/cancel_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/append_item_message_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/mark_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_self_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/cancel_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/redirect_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/publish_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/delete_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_plan_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/add_plan_step_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_plan_step_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/reject_resolution_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationCoordinationItem extends GqlNodeBase {
  MutationCoordinationItem({
    MarkBlockerCase? markBlockerCase,
    ResolveBlockerCase? resolveBlockerCase,
    CancelBlockerCase? cancelBlockerCase,
    AppendItemMessageCase? appendItemMessageCase,
    MarkAskCase? markAskCase,
    CreateSelfAskCase? createSelfAskCase,
    AcceptAskCase? acceptAskCase,
    ResolveAskCase? resolveAskCase,
    CancelAskCase? cancelAskCase,
    RedirectAskCase? redirectAskCase,
    UpdatePlanCase? updatePlanCase,
    AddPlanStepCase? addPlanStepCase,
    ResolvePlanStepCase? resolvePlanStepCase,
    CreateResolutionCase? createResolutionCase,
    AcceptResolutionCase? acceptResolutionCase,
    RejectResolutionCase? rejectResolutionCase,
    CreateDraftAskCase? createDraftAskCase,
    PublishDraftAskCase? publishDraftAskCase,
    UpdateDraftAskCase? updateDraftAskCase,
    DeleteDraftAskCase? deleteDraftAskCase,
  }) : _markBlockerCase = markBlockerCase ?? GetIt.I<MarkBlockerCase>(),
       _resolveBlockerCase =
           resolveBlockerCase ?? GetIt.I<ResolveBlockerCase>(),
       _cancelBlockerCase = cancelBlockerCase ?? GetIt.I<CancelBlockerCase>(),
       _appendItemMessageCase =
           appendItemMessageCase ?? GetIt.I<AppendItemMessageCase>(),
       _markAskCase = markAskCase ?? GetIt.I<MarkAskCase>(),
       _createSelfAskCase =
           createSelfAskCase ?? GetIt.I<CreateSelfAskCase>(),
       _acceptAskCase = acceptAskCase ?? GetIt.I<AcceptAskCase>(),
       _resolveAskCase = resolveAskCase ?? GetIt.I<ResolveAskCase>(),
       _cancelAskCase = cancelAskCase ?? GetIt.I<CancelAskCase>(),
       _redirectAskCase = redirectAskCase ?? GetIt.I<RedirectAskCase>(),
       _updatePlanCase = updatePlanCase ?? GetIt.I<UpdatePlanCase>(),
       _addPlanStepCase = addPlanStepCase ?? GetIt.I<AddPlanStepCase>(),
       _resolvePlanStepCase =
           resolvePlanStepCase ?? GetIt.I<ResolvePlanStepCase>(),
       _createResolutionCase =
           createResolutionCase ?? GetIt.I<CreateResolutionCase>(),
       _acceptResolutionCase =
           acceptResolutionCase ?? GetIt.I<AcceptResolutionCase>(),
       _rejectResolutionCase =
           rejectResolutionCase ?? GetIt.I<RejectResolutionCase>(),
       _createDraftAskCase =
           createDraftAskCase ?? GetIt.I<CreateDraftAskCase>(),
       _publishDraftAskCase =
           publishDraftAskCase ?? GetIt.I<PublishDraftAskCase>(),
       _updateDraftAskCase =
           updateDraftAskCase ?? GetIt.I<UpdateDraftAskCase>(),
       _deleteDraftAskCase =
           deleteDraftAskCase ?? GetIt.I<DeleteDraftAskCase>();

  final MarkBlockerCase _markBlockerCase;
  final ResolveBlockerCase _resolveBlockerCase;
  final CancelBlockerCase _cancelBlockerCase;
  final AppendItemMessageCase _appendItemMessageCase;
  final MarkAskCase _markAskCase;
  final CreateSelfAskCase _createSelfAskCase;
  final AcceptAskCase _acceptAskCase;
  final ResolveAskCase _resolveAskCase;
  final CancelAskCase _cancelAskCase;
  final RedirectAskCase _redirectAskCase;
  final UpdatePlanCase _updatePlanCase;
  final AddPlanStepCase _addPlanStepCase;
  final ResolvePlanStepCase _resolvePlanStepCase;
  final CreateResolutionCase _createResolutionCase;
  final AcceptResolutionCase _acceptResolutionCase;
  final RejectResolutionCase _rejectResolutionCase;
  final CreateDraftAskCase _createDraftAskCase;
  final PublishDraftAskCase _publishDraftAskCase;
  final UpdateDraftAskCase _updateDraftAskCase;
  final DeleteDraftAskCase _deleteDraftAskCase;

  final _beaconId = InputFieldString(fieldName: 'beaconId');
  final _targetItemId = InputFieldString(fieldName: 'targetItemId');
  final _targetMessageId = InputFieldString(fieldName: 'targetMessageId');
  final _parentItemId = InputFieldString(fieldName: 'parentItemId');
  final _title = InputFieldString(fieldName: 'title');
  final _body = InputFieldString(fieldName: 'body');
  final _itemId = InputFieldString(fieldName: 'itemId');
  final _linkedMessageId = InputFieldString(fieldName: 'linkedMessageId');
  final _targetPersonId = InputFieldString(fieldName: 'targetPersonId');
  final _newTargetPersonId = InputFieldString(fieldName: 'newTargetPersonId');
  final _note = InputFieldString(fieldName: 'note');
  final _reason = InputFieldString(fieldName: 'reason');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        markBlocker,
        resolveBlocker,
        cancelBlocker,
        appendCoordinationItemMessage,
        markAsk,
        createSelfAsk,
        createDraftAsk,
        publishAsk,
        updateDraftAsk,
        deleteDraftAsk,
        acceptAsk,
        resolveAsk,
        cancelAsk,
        redirectAsk,
        updateCoordinationPlan,
        addPlanStep,
        resolvePlanStep,
        createResolution,
        acceptResolution,
        rejectResolution,
      ];

  GraphQLObjectField<dynamic, dynamic> get markBlocker => GraphQLObjectField(
        'markBlocker',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _body.fieldNullable,
          _linkedMessageId.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _markBlockerCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            linkedMessageId: _linkedMessageId.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get resolveBlocker =>
      GraphQLObjectField(
        'resolveBlocker',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _note.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _resolveBlockerCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            note: _note.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get cancelBlocker => GraphQLObjectField(
        'cancelBlocker',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _reason.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _cancelBlockerCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            reason: _reason.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get appendCoordinationItemMessage =>
      GraphQLObjectField(
        'appendCoordinationItemMessage',
        gqlTypeCoordinationItemMessageRow.nonNullable(),
        arguments: [
          _itemId.field,
          _body.field,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final msg = await _appendItemMessageCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            body: _body.fromArgsNonNullable(args),
          );
          return _coordinationItemMessageToMap(msg);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get markAsk => GraphQLObjectField(
        'markAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _targetPersonId.field,
          _body.fieldNullable,
          _linkedMessageId.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _markAskCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            targetPersonId: _targetPersonId.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            linkedMessageId: _linkedMessageId.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get createSelfAsk =>
      GraphQLObjectField(
        'createSelfAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _body.fieldNullable,
          _linkedMessageId.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _createSelfAskCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            linkedMessageId: _linkedMessageId.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get createDraftAsk =>
      GraphQLObjectField(
        'createDraftAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _body.fieldNullable,
          _targetPersonId.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _createDraftAskCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            targetPersonId: _targetPersonId.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get publishAsk => GraphQLObjectField(
        'publishAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _targetPersonId.field,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _publishDraftAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            targetPersonId: _targetPersonId.fromArgsNonNullable(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get updateDraftAsk =>
      GraphQLObjectField(
        'updateDraftAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _title.field,
          _body.fieldNullable,
          _targetPersonId.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final hasTarget = args.containsKey('targetPersonId');
          final item = await _updateDraftAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            updateTargetPersonId: hasTarget,
            targetPersonId: _targetPersonId.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get deleteDraftAsk =>
      GraphQLObjectField(
        'deleteDraftAsk',
        graphQLBoolean.nonNullable(),
        arguments: [_itemId.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final ok = await _deleteDraftAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
          );
          return ok;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get acceptAsk => GraphQLObjectField(
        'acceptAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [_itemId.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _acceptAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get resolveAsk => GraphQLObjectField(
        'resolveAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _note.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _resolveAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            note: _note.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get cancelAsk => GraphQLObjectField(
        'cancelAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _reason.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _cancelAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            reason: _reason.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get redirectAsk => GraphQLObjectField(
        'redirectAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _newTargetPersonId.field,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _redirectAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            newTargetPersonId: _newTargetPersonId.fromArgsNonNullable(args),
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
          _linkedMessageId.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _updatePlanCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
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

  GraphQLObjectField<dynamic, dynamic> get createResolution =>
      GraphQLObjectField(
        'createResolution',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _body.fieldNullable,
          _targetItemId.fieldNullable,
          _targetMessageId.fieldNullable,
          _linkedMessageId.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _createResolutionCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            targetItemId: _targetItemId.fromArgs(args),
            targetMessageId: _targetMessageId.fromArgs(args),
            linkedMessageId: _linkedMessageId.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get acceptResolution =>
      GraphQLObjectField(
        'acceptResolution',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _acceptResolutionCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get rejectResolution =>
      GraphQLObjectField(
        'rejectResolution',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _reason.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _rejectResolutionCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            reason: _reason.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
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
      'source': item.source,
      'published': item.published,
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
