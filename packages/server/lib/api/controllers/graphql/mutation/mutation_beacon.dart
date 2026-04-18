import 'package:tentura_server/domain/use_case/beacon_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationBeacon extends GqlNodeBase {
  MutationBeacon({BeaconCase? beaconCase})
    : _beaconCase = beaconCase ?? GetIt.I<BeaconCase>();

  final BeaconCase _beaconCase;

  final _startAt = InputFieldDatetime(fieldName: 'startAt');

  final _endAt = InputFieldDatetime(fieldName: 'endAt');

  final _tags = InputFieldString(fieldName: 'tags');

  final _iconCode = InputFieldString(fieldName: 'iconCode');

  final _iconBackground = InputFieldInt(fieldName: 'iconBackground');

  final _draft = InputFieldBool(fieldName: 'draft');

  final _beaconId = InputFieldString(fieldName: 'beaconId');

  final _imageId = InputFieldString(fieldName: 'imageId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    create,
    update,
    updateDraft,
    deleteById,
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

  GraphQLObjectField<dynamic, dynamic> get create => GraphQLObjectField(
    'beaconCreate',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldTitle.fieldNonNullable,
      InputFieldDescription.field,
      InputFieldCoordinates.field,
      InputFieldUpload.fieldImage,
      InputFieldContext.field,
      InputFieldPolling.field,
      _startAt.fieldNullable,
      _endAt.fieldNullable,
      _tags.fieldNullable,
      _iconCode.fieldNullable,
      _iconBackground.fieldNullable,
      _draft.fieldNullable,
    ],
    resolve: (_, args) => _beaconCase
        .create(
          userId: getCredentials(args).sub,
          title: InputFieldTitle.fromArgsNonNullable(args),
          description: InputFieldDescription.fromArgs(args),
          coordinates: InputFieldCoordinates.fromArgs(args),
          imageBytes: InputFieldUpload.fromArgs(args),
          context: InputFieldContext.fromArgs(args),
          polling: InputFieldPolling.fromArgs(args),
          startAt: _startAt.fromArgs(args),
          endAt: _endAt.fromArgs(args),
          tags: _tags.fromArgs(args),
          iconCode: _iconCode.fromArgs(args),
          iconBackground: _iconBackground.fromArgs(args),
          draft: _draft.fromArgs(args) ?? false,
        )
        .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get update => GraphQLObjectField(
    'beaconUpdate',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldTitle.fieldNonNullable,
      InputFieldDescription.field,
      InputFieldCoordinates.field,
      InputFieldContext.field,
      _startAt.fieldNullable,
      _endAt.fieldNullable,
      _tags.fieldNullable,
      _iconCode.fieldNullable,
      _iconBackground.fieldNullable,
    ],
    resolve: (_, args) => _beaconCase
        .update(
          userId: getCredentials(args).sub,
          beaconId: InputFieldId.fromArgsNonNullable(args),
          title: InputFieldTitle.fromArgsNonNullable(args),
          description: InputFieldDescription.fromArgs(args),
          coordinates: InputFieldCoordinates.fromArgs(args),
          context: InputFieldContext.fromArgs(args),
          startAt: _startAt.fromArgs(args),
          endAt: _endAt.fromArgs(args),
          tags: _tags.fromArgs(args),
          iconCode: _iconCode.fromArgs(args),
          iconBackground: _iconBackground.fromArgs(args),
        )
        .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get updateDraft => GraphQLObjectField(
    'beaconUpdateDraft',
    gqlTypeBeacon.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldTitle.fieldNonNullable,
      InputFieldDescription.field,
      InputFieldCoordinates.field,
      InputFieldContext.field,
      InputFieldPolling.field,
      _startAt.fieldNullable,
      _endAt.fieldNullable,
      _tags.fieldNullable,
      _iconCode.fieldNullable,
      _iconBackground.fieldNullable,
    ],
    resolve: (_, args) => _beaconCase
        .updateDraft(
          userId: getCredentials(args).sub,
          beaconId: InputFieldId.fromArgsNonNullable(args),
          title: InputFieldTitle.fromArgsNonNullable(args),
          description: InputFieldDescription.fromArgs(args),
          coordinates: InputFieldCoordinates.fromArgs(args),
          context: InputFieldContext.fromArgs(args),
          polling: InputFieldPolling.fromArgs(args),
          startAt: _startAt.fromArgs(args),
          endAt: _endAt.fromArgs(args),
          tags: _tags.fromArgs(args),
          iconCode: _iconCode.fromArgs(args),
          iconBackground: _iconBackground.fromArgs(args),
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
