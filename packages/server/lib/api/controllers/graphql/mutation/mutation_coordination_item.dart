import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/use_case/coordination_item/mark_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/cancel_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/mark_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_draft_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/publish_draft_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_draft_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/delete_draft_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/cancel_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/redirect_promise_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/cancel_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/redirect_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/publish_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/delete_draft_ask_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_draft_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/publish_draft_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_draft_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/delete_draft_blocker_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_plan_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/add_plan_step_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/resolve_plan_step_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/create_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/accept_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/reject_resolution_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/update_coordination_item_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/remind_coordination_item_case.dart';
import 'package:tentura_server/domain/use_case/coordination_item/coordination_responsibility_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationCoordinationItem extends GqlNodeBase {
  MutationCoordinationItem({
    MarkBlockerCase? markBlockerCase,
    ResolveBlockerCase? resolveBlockerCase,
    CancelBlockerCase? cancelBlockerCase,
    MarkAskCase? markAskCase,
    CreatePromiseCase? createPromiseCase,
    CreateDraftPromiseCase? createDraftPromiseCase,
    PublishDraftPromiseCase? publishDraftPromiseCase,
    UpdateDraftPromiseCase? updateDraftPromiseCase,
    DeleteDraftPromiseCase? deleteDraftPromiseCase,
    AcceptPromiseCase? acceptPromiseCase,
    ResolvePromiseCase? resolvePromiseCase,
    CancelPromiseCase? cancelPromiseCase,
    RedirectPromiseCase? redirectPromiseCase,
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
    CreateDraftBlockerCase? createDraftBlockerCase,
    PublishDraftBlockerCase? publishDraftBlockerCase,
    UpdateDraftBlockerCase? updateDraftBlockerCase,
    DeleteDraftBlockerCase? deleteDraftBlockerCase,
    UpdateCoordinationItemCase? updateCoordinationItemCase,
    RemindCoordinationItemCase? remindCoordinationItemCase,
    CoordinationResponsibilityCase? responsibilityCase,
  }) : _markBlockerCase = markBlockerCase ?? GetIt.I<MarkBlockerCase>(),
       _resolveBlockerCase =
           resolveBlockerCase ?? GetIt.I<ResolveBlockerCase>(),
       _cancelBlockerCase = cancelBlockerCase ?? GetIt.I<CancelBlockerCase>(),
       _markAskCase = markAskCase ?? GetIt.I<MarkAskCase>(),
       _createPromiseCase =
           createPromiseCase ?? GetIt.I<CreatePromiseCase>(),
       _createDraftPromiseCase =
           createDraftPromiseCase ?? GetIt.I<CreateDraftPromiseCase>(),
       _publishDraftPromiseCase =
           publishDraftPromiseCase ?? GetIt.I<PublishDraftPromiseCase>(),
       _updateDraftPromiseCase =
           updateDraftPromiseCase ?? GetIt.I<UpdateDraftPromiseCase>(),
       _deleteDraftPromiseCase =
           deleteDraftPromiseCase ?? GetIt.I<DeleteDraftPromiseCase>(),
       _acceptPromiseCase =
           acceptPromiseCase ?? GetIt.I<AcceptPromiseCase>(),
       _resolvePromiseCase =
           resolvePromiseCase ?? GetIt.I<ResolvePromiseCase>(),
       _cancelPromiseCase =
           cancelPromiseCase ?? GetIt.I<CancelPromiseCase>(),
       _redirectPromiseCase =
           redirectPromiseCase ?? GetIt.I<RedirectPromiseCase>(),
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
           deleteDraftAskCase ?? GetIt.I<DeleteDraftAskCase>(),
       _createDraftBlockerCase =
           createDraftBlockerCase ?? GetIt.I<CreateDraftBlockerCase>(),
       _publishDraftBlockerCase =
           publishDraftBlockerCase ?? GetIt.I<PublishDraftBlockerCase>(),
       _updateDraftBlockerCase =
           updateDraftBlockerCase ?? GetIt.I<UpdateDraftBlockerCase>(),
       _deleteDraftBlockerCase =
           deleteDraftBlockerCase ?? GetIt.I<DeleteDraftBlockerCase>(),
       _updateCoordinationItemCase =
           updateCoordinationItemCase ?? GetIt.I<UpdateCoordinationItemCase>(),
       _remindCoordinationItemCase =
           remindCoordinationItemCase ?? GetIt.I<RemindCoordinationItemCase>(),
       _responsibilityCase =
           responsibilityCase ?? GetIt.I<CoordinationResponsibilityCase>();

  final MarkBlockerCase _markBlockerCase;
  final ResolveBlockerCase _resolveBlockerCase;
  final CancelBlockerCase _cancelBlockerCase;
  final MarkAskCase _markAskCase;
  final CreatePromiseCase _createPromiseCase;
  final CreateDraftPromiseCase _createDraftPromiseCase;
  final PublishDraftPromiseCase _publishDraftPromiseCase;
  final UpdateDraftPromiseCase _updateDraftPromiseCase;
  final DeleteDraftPromiseCase _deleteDraftPromiseCase;
  final AcceptPromiseCase _acceptPromiseCase;
  final ResolvePromiseCase _resolvePromiseCase;
  final CancelPromiseCase _cancelPromiseCase;
  final RedirectPromiseCase _redirectPromiseCase;
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
  final CreateDraftBlockerCase _createDraftBlockerCase;
  final PublishDraftBlockerCase _publishDraftBlockerCase;
  final UpdateDraftBlockerCase _updateDraftBlockerCase;
  final DeleteDraftBlockerCase _deleteDraftBlockerCase;
  final UpdateCoordinationItemCase _updateCoordinationItemCase;
  final RemindCoordinationItemCase _remindCoordinationItemCase;
  final CoordinationResponsibilityCase _responsibilityCase;

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
  final _staleAfterDays = InputFieldInt(fieldName: 'staleAfterDays');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        markBlocker,
        resolveBlocker,
        cancelBlocker,
        markAsk,
        createPromise,
        createDraftPromise,
        publishPromise,
        updateDraftPromise,
        deleteDraftPromise,
        acceptPromise,
        resolvePromise,
        cancelPromise,
        redirectPromise,
        createDraftAsk,
        publishAsk,
        updateDraftAsk,
        deleteDraftAsk,
        createDraftBlocker,
        publishBlocker,
        updateDraftBlocker,
        deleteDraftBlocker,
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
        updateCoordinationItem,
        remindCoordinationItem,
        markBeaconItemsSeen,
      ];

  GraphQLObjectField<dynamic, dynamic> get markBlocker => GraphQLObjectField(
        'markBlocker',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _body.fieldNullable,
          _targetPersonId.fieldNullable,
          _linkedMessageId.fieldNullable,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _markBlockerCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            targetPersonId: _targetPersonId.fromArgs(args),
            linkedMessageId: _linkedMessageId.fromArgs(args),
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
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

  GraphQLObjectField<dynamic, dynamic> get markAsk => GraphQLObjectField(
        'markAsk',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _targetPersonId.field,
          _body.fieldNullable,
          _linkedMessageId.fieldNullable,
          _staleAfterDays.fieldNullable,
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
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get createPromise =>
      GraphQLObjectField(
        'createPromise',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _targetPersonId.field,
          _body.fieldNullable,
          _linkedMessageId.fieldNullable,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _createPromiseCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            targetPersonId: _targetPersonId.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            linkedMessageId: _linkedMessageId.fromArgs(args),
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get createDraftPromise =>
      GraphQLObjectField(
        'createDraftPromise',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _body.fieldNullable,
          _targetPersonId.fieldNullable,
          _linkedMessageId.fieldNullable,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _createDraftPromiseCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            targetPersonId: _targetPersonId.fromArgs(args),
            linkedMessageId: _linkedMessageId.fromArgs(args),
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get publishPromise =>
      GraphQLObjectField(
        'publishPromise',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _targetPersonId.field,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _publishDraftPromiseCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            targetPersonId: _targetPersonId.fromArgsNonNullable(args),
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get updateDraftPromise =>
      GraphQLObjectField(
        'updateDraftPromise',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _title.field,
          _body.fieldNullable,
          _targetPersonId.fieldNullable,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final hasTarget = args.containsKey('targetPersonId');
          // Only a concrete value updates the window; an explicit null (or an
          // omitted arg) leaves the stored deadline untouched rather than
          // clobbering it with the default. Pass 0 to clear a deadline.
          final hasStale = args['staleAfterDays'] != null;
          final item = await _updateDraftPromiseCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            updateTargetPersonId: hasTarget,
            targetPersonId: _targetPersonId.fromArgs(args),
            updateStaleAfterDays: hasStale,
            staleAfterDays: _staleAfterDays.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get deleteDraftPromise =>
      GraphQLObjectField(
        'deleteDraftPromise',
        graphQLBoolean.nonNullable(),
        arguments: [_itemId.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final ok = await _deleteDraftPromiseCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
          );
          return ok;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get acceptPromise =>
      GraphQLObjectField(
        'acceptPromise',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [_itemId.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _acceptPromiseCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get resolvePromise =>
      GraphQLObjectField(
        'resolvePromise',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _note.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _resolvePromiseCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            note: _note.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get cancelPromise =>
      GraphQLObjectField(
        'cancelPromise',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _reason.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _cancelPromiseCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            reason: _reason.fromArgs(args) ?? '',
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get redirectPromise =>
      GraphQLObjectField(
        'redirectPromise',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _newTargetPersonId.field,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _redirectPromiseCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            newTargetPersonId: _newTargetPersonId.fromArgsNonNullable(args),
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
          _linkedMessageId.fieldNullable,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _createDraftAskCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            targetPersonId: _targetPersonId.fromArgs(args),
            linkedMessageId: _linkedMessageId.fromArgs(args),
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
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
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _publishDraftAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            targetPersonId: _targetPersonId.fromArgsNonNullable(args),
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
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
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final hasTarget = args.containsKey('targetPersonId');
          // Only a concrete value updates the window; an explicit null (or an
          // omitted arg) leaves the stored deadline untouched rather than
          // clobbering it with the default. Pass 0 to clear a deadline.
          final hasStale = args['staleAfterDays'] != null;
          final item = await _updateDraftAskCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            updateTargetPersonId: hasTarget,
            targetPersonId: _targetPersonId.fromArgs(args),
            updateStaleAfterDays: hasStale,
            staleAfterDays: _staleAfterDays.fromArgs(args),
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

  GraphQLObjectField<dynamic, dynamic> get createDraftBlocker =>
      GraphQLObjectField(
        'createDraftBlocker',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _beaconId.field,
          _title.field,
          _body.fieldNullable,
          _targetPersonId.fieldNullable,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _createDraftBlockerCase.call(
            userId: userId,
            beaconId: _beaconId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            targetPersonId: _targetPersonId.fromArgs(args),
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get publishBlocker =>
      GraphQLObjectField(
        'publishBlocker',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final item = await _publishDraftBlockerCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            staleAfterDays: _staleAfterDaysFromArgs(args, _staleAfterDays),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get updateDraftBlocker =>
      GraphQLObjectField(
        'updateDraftBlocker',
        gqlTypeCoordinationItemRow.nonNullable(),
        arguments: [
          _itemId.field,
          _title.field,
          _body.fieldNullable,
          _targetPersonId.fieldNullable,
          _staleAfterDays.fieldNullable,
        ],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final hasTarget = args.containsKey('targetPersonId');
          // Only a concrete value updates the window; an explicit null (or an
          // omitted arg) leaves the stored deadline untouched rather than
          // clobbering it with the default. Pass 0 to clear a deadline.
          final hasStale = args['staleAfterDays'] != null;
          final item = await _updateDraftBlockerCase.call(
            userId: userId,
            itemId: _itemId.fromArgsNonNullable(args),
            title: _title.fromArgsNonNullable(args),
            body: _body.fromArgs(args) ?? '',
            updateTargetPersonId: hasTarget,
            targetPersonId: _targetPersonId.fromArgs(args),
            updateStaleAfterDays: hasStale,
            staleAfterDays: _staleAfterDays.fromArgs(args),
          );
          return _coordinationItemToMap(item);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get deleteDraftBlocker =>
      GraphQLObjectField(
        'deleteDraftBlocker',
        graphQLBoolean.nonNullable(),
        arguments: [_itemId.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          final ok = await _deleteDraftBlockerCase.call(
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

int? _staleAfterDaysFromArgs(
  Map<String, dynamic> args,
  InputFieldInt field,
) =>
    args.containsKey('staleAfterDays') ? field.fromArgs(args) : null;

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
      'staleAt': item.staleAt?.dateTime.toIso8601String(),
      'lastRemindedAt': item.lastRemindedAt?.dateTime.toIso8601String(),
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
