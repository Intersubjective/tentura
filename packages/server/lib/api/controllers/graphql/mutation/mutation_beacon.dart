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

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    create,
    deleteById,
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
        )
        .then((v) => v.asJson),
  );
}
