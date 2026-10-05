import 'package:tentura_server/domain/entity/beacon_conversion_content.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_v2_dto_maps.dart';

/// `[PlanStepTimeInput!]` typed over `dynamic`, so a decoded `List<dynamic>`
/// of maps passes validation on executors that do not re-type variable lists.
final class _PlanStepTimeListType extends GraphQLListType<dynamic, dynamic> {
  _PlanStepTimeListType() : super(gqlInputPlanStepTime.nonNullable());

  @override
  GraphQLType<List<dynamic>, List<dynamic>> coerceToInputObject() => this;
}

final class MutationBeacon extends GqlNodeBase {
  MutationBeacon({BeaconCase? beaconCase})
    : _beaconCase = beaconCase ?? GetIt.I<BeaconCase>();

  final BeaconCase _beaconCase;

  final _startAt = InputFieldDatetime(fieldName: 'startAt');

  final _endAt = InputFieldDatetime(fieldName: 'endAt');

  final _tags = InputFieldString(fieldName: 'tags');

  final _needs = InputFieldString(fieldName: 'needs');

  final _addressLabel = InputFieldString(fieldName: 'addressLabel');

  final _draft = InputFieldBool(fieldName: 'draft');

  final _beaconId = InputFieldString(fieldName: 'beaconId');

  final _imageId = InputFieldString(fieldName: 'imageId');

  final _primaryNeedSlug = InputFieldString(fieldName: 'primaryNeedSlug');

  final _isDiscoverable = InputFieldBool(fieldName: 'isDiscoverable');

  final _kind = InputFieldInt(fieldName: 'kind');

  final _forwardPolicy = InputFieldInt(fieldName: 'forwardPolicy');

  final _copyPlan = InputFieldBool(fieldName: 'copyPlan');

  final _planStepTimes = GraphQLFieldInput(
    'planStepTimes',
    _PlanStepTimeListType(),
    defaultsToNull: true,
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    create,
    fork,
    update,
    updateDraft,
    convertToRequest,
    publish,
    deleteById,
    beaconCancel,
    beaconForwardingOpen,
    addImage,
    removeImage,
    reorderImages,
    stageImage,
    setMedia,
  ];

  GraphQLObjectField<dynamic, dynamic> get deleteById => GraphQLObjectField(
    'beaconDeleteById',
    graphQLBoolean.nonNullable(),
    arguments: [InputFieldId.field],
    resolve: (_, args) => _beaconCase.deleteById(
      beaconId: InputFieldId.fromArgsNonNullable(args),
      userId: getCredentials(args).sub,
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get beaconForwardingOpen =>
      GraphQLObjectField(
        'beaconForwardingOpen',
        graphQLBoolean,
        arguments: [InputFieldId.field],
        resolve: (_, args) => _beaconCase.openForwarding(
          authorId: getCredentials(args).sub,
          id: InputFieldId.fromArgsNonNullable(args),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconCancel => GraphQLObjectField(
    'beaconCancel',
    gqlTypeBeaconCancelResult.nonNullable(),
    arguments: [InputFieldId.field],
    resolve: (_, args) => _beaconCase
        .beaconCancel(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        )
        .then(beaconCancelResultToGqlMap),
  );

  GraphQLObjectField<dynamic, dynamic> get create => GraphQLObjectField(
    'beaconCreate',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldBeaconTitle.field,
      InputFieldDescription.field,
      InputFieldCoordinates.field,
      InputFieldUpload.fieldImage,
      InputFieldContext.field,
      _startAt.fieldNullable,
      _endAt.fieldNullable,
      _tags.fieldNullable,
      _needs.fieldNullable,
      _primaryNeedSlug.fieldNullable,
      _addressLabel.fieldNullable,
      _draft.fieldNullable,
      _isDiscoverable.fieldNullable,
      _kind.fieldNullable,
      _forwardPolicy.fieldNullable,
    ],
    resolve: (_, args) {
      final kindValue = _kind.fromArgs(args);
      final kind = kindValue == null
          ? BeaconKind.request
          : BeaconKind.fromValue(kindValue);
      final title = InputFieldBeaconTitle.fromArgs(args);
      if (title == null && kind != BeaconKind.post) {
        throw GraphQLException([
          GraphQLExceptionError(
            'Missing value for argument "title" of field "beaconCreate".',
          ),
        ]);
      }
      final forwardPolicyValue = _forwardPolicy.fromArgs(args);
      return _beaconCase
          .create(
            userId: getCredentials(args).sub,
            title: title ?? '',
            kind: kind,
            forwardPolicy: forwardPolicyValue == null
                ? BeaconForwardPolicyValue.open
                : BeaconForwardPolicyValue.fromValue(forwardPolicyValue),
            description: InputFieldDescription.fromArgs(args),
            coordinates: InputFieldCoordinates.fromArgs(args),
            imageBytes: InputFieldUpload.fromArgs(args),
            context: InputFieldContext.fromArgs(args),
            startAt: _startAt.fromArgs(args),
            endAt: _endAt.fromArgs(args),
            tags: _tags.fromArgs(args),
            needs: _needs.fromArgs(args),
            primaryNeedSlug: _primaryNeedSlug.fromArgs(args),
            primaryNeedSlugProvided: args.containsKey('primaryNeedSlug'),
            draft: _draft.fromArgs(args) ?? false,
            addressLabel: _addressLabel.fromArgs(args),
            isDiscoverable: _isDiscoverable.fromArgs(args),
          )
          .then((v) => v.asJson);
    },
  );

  GraphQLObjectField<dynamic, dynamic> get fork => GraphQLObjectField(
    'beaconFork',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldId.field,
      _copyPlan.fieldNullable,
      _planStepTimes,
    ],
    resolve: (_, args) => _beaconCase
        .fork(
          sourceId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          copyPlan: _copyPlan.fromArgs(args) ?? false,
          planStepTimes: _parsePlanStepTimes(args[_planStepTimes.name]),
        )
        .then((v) => v.asJson),
  );

  static Map<String, ({DateTime? startAt, DateTime? endAt})>
  _parsePlanStepTimes(Object? raw) {
    if (raw is! List) return const {};
    // Like `InputFieldDatetime`: an offset-less value is read as UTC.
    DateTime? instant(Object? v) {
      final p = v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
      if (p == null || p.isUtc) return p;
      return DateTime.utc(
        p.year,
        p.month,
        p.day,
        p.hour,
        p.minute,
        p.second,
        p.millisecond,
        p.microsecond,
      );
    }

    return {
      for (final entry in raw)
        if (entry is Map && entry['sourceStepId'] is String)
          entry['sourceStepId'] as String: (
            startAt: instant(entry['startAt']),
            endAt: instant(entry['endAt']),
          ),
    };
  }

  GraphQLObjectField<dynamic, dynamic> get update => GraphQLObjectField(
    'beaconUpdate',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldBeaconTitle.fieldNonNullable,
      InputFieldDescription.field,
      InputFieldCoordinates.field,
      InputFieldContext.field,
      _startAt.fieldNullable,
      _endAt.fieldNullable,
      _tags.fieldNullable,
      _needs.fieldNullable,
      _primaryNeedSlug.fieldNullable,
      _addressLabel.fieldNullable,
      _isDiscoverable.fieldNullable,
    ],
    resolve: (_, args) => _beaconCase
        .update(
          userId: getCredentials(args).sub,
          beaconId: InputFieldId.fromArgsNonNullable(args),
          title: InputFieldBeaconTitle.fromArgsNonNullable(args),
          description: InputFieldDescription.fromArgs(args),
          coordinates: InputFieldCoordinates.fromArgs(args),
          context: InputFieldContext.fromArgs(args),
          startAt: _startAt.fromArgs(args),
          endAt: _endAt.fromArgs(args),
          tags: _tags.fromArgs(args),
          needs: _needs.fromArgs(args),
          primaryNeedSlug: _primaryNeedSlug.fromArgs(args),
          primaryNeedSlugProvided: args.containsKey('primaryNeedSlug'),
          addressLabel: _addressLabel.fromArgs(args),
          isDiscoverable: _isDiscoverable.fromArgs(args),
          isDiscoverableProvided: args.containsKey('isDiscoverable'),
        )
        .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get updateDraft => GraphQLObjectField(
    'beaconUpdateDraft',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldBeaconTitle.fieldNonNullable,
      InputFieldDescription.field,
      InputFieldCoordinates.field,
      InputFieldContext.field,
      _startAt.fieldNullable,
      _endAt.fieldNullable,
      _tags.fieldNullable,
      _needs.fieldNullable,
      _primaryNeedSlug.fieldNullable,
      _addressLabel.fieldNullable,
      _isDiscoverable.fieldNullable,
    ],
    resolve: (_, args) => _beaconCase
        .updateDraft(
          userId: getCredentials(args).sub,
          beaconId: InputFieldId.fromArgsNonNullable(args),
          title: InputFieldBeaconTitle.fromArgsNonNullable(args),
          description: InputFieldDescription.fromArgs(args),
          coordinates: InputFieldCoordinates.fromArgs(args),
          context: InputFieldContext.fromArgs(args),
          startAt: _startAt.fromArgs(args),
          endAt: _endAt.fromArgs(args),
          tags: _tags.fromArgs(args),
          needs: _needs.fromArgs(args),
          primaryNeedSlug: _primaryNeedSlug.fromArgs(args),
          primaryNeedSlugProvided: args.containsKey('primaryNeedSlug'),
          addressLabel: _addressLabel.fromArgs(args),
          isDiscoverable: _isDiscoverable.fromArgs(args),
          isDiscoverableProvided: args.containsKey('isDiscoverable'),
        )
        .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get convertToRequest =>
      GraphQLObjectField(
        'beaconConvertToRequest',
        gqlTypeBeacon.nonNullable(),
        arguments: [
          InputFieldId.field,
          InputFieldBeaconTitle.fieldNonNullable,
          InputFieldDescription.field,
          _startAt.fieldNullable,
          _endAt.fieldNullable,
          _needs.fieldNullable,
          _primaryNeedSlug.fieldNullable,
          _isDiscoverable.fieldNullable,
        ],
        resolve: (_, args) => _beaconCase
            .convertToRequest(
              authorId: getCredentials(args).sub,
              beaconId: InputFieldId.fromArgsNonNullable(args),
              content: BeaconConversionContent(
                title: InputFieldBeaconTitle.fromArgsNonNullable(args),
                description: InputFieldDescription.fromArgs(args),
                needs: _needs.fromArgs(args),
                primaryNeedSlug: _primaryNeedSlug.fromArgs(args),
                startAt: _startAt.fromArgs(args),
                endAt: _endAt.fromArgs(args),
              ),
              isDiscoverable: _isDiscoverable.fromArgs(args) ?? true,
            )
            .then((v) => v.asJson),
      );

  GraphQLObjectField<dynamic, dynamic> get publish => GraphQLObjectField(
    'beaconPublish',
    gqlTypeBeacon.nonNullable(),
    arguments: [InputFieldId.field],
    resolve: (_, args) => _beaconCase
        .publishDraft(
          userId: getCredentials(args).sub,
          beaconId: InputFieldId.fromArgsNonNullable(args),
        )
        .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get addImage => GraphQLObjectField(
    'beaconAddImage',
    gqlTypeBeaconImageAdded.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldUpload.fieldImage,
    ],
    resolve: (_, args) => _beaconCase
        .addImage(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          imageBytes: InputFieldUpload.fromArgs(args)!,
        )
        .then(beaconImageAddedResultToGqlMap),
  );

  GraphQLObjectField<dynamic, dynamic> get stageImage => GraphQLObjectField(
    'beaconStageImage',
    gqlTypeBeaconImageStaged.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldUpload.fieldImage,
    ],
    resolve: (_, args) => _beaconCase
        .beaconStageImage(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          imageBytes: InputFieldUpload.fromArgs(args)!,
        )
        .then(beaconImageStagedResultToGqlMap),
  );

  GraphQLObjectField<dynamic, dynamic> get setMedia => GraphQLObjectField(
    'beaconSetMedia',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldBeaconMedia.imageIds,
      InputFieldBeaconMedia.coverImageId,
      InputFieldBeaconMedia.coverThumbImageId,
      InputFieldBeaconMedia.coverSource,
    ],
    resolve: (_, args) => _beaconCase
        .beaconSetMedia(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          imageIds: InputFieldBeaconMedia.imageIdsFromArgs(args),
          coverImageId: InputFieldBeaconMedia.coverImageIdFromArgs(args),
          coverThumbImageId: InputFieldBeaconMedia.coverThumbImageIdFromArgs(
            args,
          ),
          coverThumbImageIdPresent:
              InputFieldBeaconMedia.coverThumbImageIdPresent(args),
          coverSource: InputFieldBeaconMedia.coverSourceFromArgs(args),
        )
        .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get removeImage => GraphQLObjectField(
    'beaconRemoveImage',
    graphQLBoolean.nonNullable(),
    arguments: [
      _beaconId.field,
      _imageId.field,
    ],
    resolve: (_, args) => _beaconCase.removeImage(
      beaconId: _beaconId.fromArgsNonNullable(args),
      imageId: _imageId.fromArgsNonNullable(args),
      userId: getCredentials(args).sub,
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get reorderImages => GraphQLObjectField(
    'beaconReorderImages',
    graphQLBoolean.nonNullable(),
    arguments: [
      _beaconId.field,
      InputFieldImageIds.field,
    ],
    resolve: (_, args) => _beaconCase.reorderImages(
      beaconId: _beaconId.fromArgsNonNullable(args),
      userId: getCredentials(args).sub,
      imageIds: InputFieldImageIds.fromArgs(args),
    ),
  );
}
