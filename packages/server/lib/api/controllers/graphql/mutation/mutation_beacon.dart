import 'package:tentura_server/domain/use_case/beacon_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_v2_dto_maps.dart';

final class MutationBeacon extends GqlNodeBase {
  MutationBeacon({BeaconCase? beaconCase})
    : _beaconCase = beaconCase ?? GetIt.I<BeaconCase>();

  final BeaconCase _beaconCase;

  final _startAt = InputFieldDatetime(fieldName: 'startAt');

  final _endAt = InputFieldDatetime(fieldName: 'endAt');

  final _tags = InputFieldString(fieldName: 'tags');

  final _iconCode = InputFieldString(fieldName: 'iconCode');

  final _iconBackground = InputFieldInt(fieldName: 'iconBackground');

  final _needSummary = InputFieldString(fieldName: 'needSummary');

  final _successCriteria = InputFieldString(fieldName: 'successCriteria');

  final _needs = InputFieldString(fieldName: 'needs');

  final _addressLabel = InputFieldString(fieldName: 'addressLabel');

  final _draft = InputFieldBool(fieldName: 'draft');

  final _beaconId = InputFieldString(fieldName: 'beaconId');

  final _imageId = InputFieldString(fieldName: 'imageId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    create,
    fork,
    update,
    updateDraft,
    publish,
    deleteById,
    beaconCancel,
    addImage,
    removeImage,
    reorderImages,
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

  GraphQLObjectField<dynamic, dynamic> get beaconCancel => GraphQLObjectField(
    'beaconCancel',
    gqlTypeBeaconCloseReviewResult.nonNullable(),
    arguments: [InputFieldId.field],
    resolve: (_, args) => _beaconCase
        .beaconCancel(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        )
        .then(beaconCloseReviewResultToGqlMap),
  );

  GraphQLObjectField<dynamic, dynamic> get create => GraphQLObjectField(
    'beaconCreate',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldBeaconTitle.fieldNonNullable,
      InputFieldDescription.field,
      InputFieldCoordinates.field,
      InputFieldUpload.fieldImage,
      InputFieldContext.field,
      _startAt.fieldNullable,
      _endAt.fieldNullable,
      _tags.fieldNullable,
      _iconCode.fieldNullable,
      _iconBackground.fieldNullable,
      _needSummary.fieldNullable,
      _successCriteria.fieldNullable,
      _needs.fieldNullable,
      _addressLabel.fieldNullable,
      _draft.fieldNullable,
    ],
    resolve: (_, args) => _beaconCase
        .create(
          userId: getCredentials(args).sub,
          title: InputFieldBeaconTitle.fromArgsNonNullable(args),
          description: InputFieldDescription.fromArgs(args),
          coordinates: InputFieldCoordinates.fromArgs(args),
          imageBytes: InputFieldUpload.fromArgs(args),
          context: InputFieldContext.fromArgs(args),
          startAt: _startAt.fromArgs(args),
          endAt: _endAt.fromArgs(args),
          tags: _tags.fromArgs(args),
          needs: _needs.fromArgs(args),
          iconCode: _iconCode.fromArgs(args),
          iconBackground: _iconBackground.fromArgs(args),
          draft: _draft.fromArgs(args) ?? false,
          needSummary: _needSummary.fromArgs(args),
          successCriteria: _successCriteria.fromArgs(args),
          addressLabel: _addressLabel.fromArgs(args),
        )
        .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get fork => GraphQLObjectField(
    'beaconFork',
    gqlTypeBeacon.nonNullable(),
    arguments: [InputFieldId.field],
    resolve: (_, args) => _beaconCase
        .fork(
          sourceId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        )
        .then((v) => v.asJson),
  );

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
      _iconCode.fieldNullable,
      _iconBackground.fieldNullable,
      _needSummary.fieldNullable,
      _successCriteria.fieldNullable,
      _needs.fieldNullable,
      _addressLabel.fieldNullable,
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
          iconCode: _iconCode.fromArgs(args),
          iconBackground: _iconBackground.fromArgs(args),
          needSummary: _needSummary.fromArgs(args),
          successCriteria: _successCriteria.fromArgs(args),
          addressLabel: _addressLabel.fromArgs(args),
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
      _iconCode.fieldNullable,
      _iconBackground.fieldNullable,
      _needSummary.fieldNullable,
      _successCriteria.fieldNullable,
      _needs.fieldNullable,
      _addressLabel.fieldNullable,
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
          iconCode: _iconCode.fromArgs(args),
          iconBackground: _iconBackground.fromArgs(args),
          needSummary: _needSummary.fromArgs(args),
          successCriteria: _successCriteria.fromArgs(args),
          addressLabel: _addressLabel.fromArgs(args),
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
    gqlTypeBeacon.nonNullable(),
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
