import 'package:tentura_server/domain/use_case/beacon_people_seen_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// `String` scalar that accepts an explicit `null` variable, so the nullable
/// argument also works on executors without the null-safe argument coercion
/// of the production schema.
final class _NullableStringType extends GraphQLScalarType<String?, String?> {
  @override
  String get name => 'String';

  @override
  String get description => 'A character sequence.';

  @override
  GraphQLType<String?, String?> coerceToInputObject() => this;

  @override
  String? serialize(String? value) => value;

  @override
  String? deserialize(String? serialized) => serialized;

  @override
  ValidationResult<String?> validate(String key, Object? input) =>
      graphQLString.validate(key, input ?? '');
}

final class MutationBeaconPeople extends GqlNodeBase {
  MutationBeaconPeople({BeaconPeopleSeenCase? beaconPeopleSeenCase})
    : _case = beaconPeopleSeenCase ?? GetIt.I<BeaconPeopleSeenCase>();

  final BeaconPeopleSeenCase _case;

  final _beaconId = InputFieldString(fieldName: 'beaconId');

  final _readThroughAt = GraphQLFieldInput<String?, String?>(
    'readThroughAt',
    _NullableStringType(),
    defaultsToNull: true,
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [markBeaconPeopleSeen];

  GraphQLObjectField<dynamic, dynamic> get markBeaconPeopleSeen =>
      GraphQLObjectField(
        'MarkBeaconPeopleSeen',
        gqlTypeBeaconPeopleSeenResult.nonNullable(),
        arguments: [_beaconId.field, _readThroughAt],
        resolve: (_, args) => _case.markPeopleSeen(
          beaconId: _beaconId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          readThroughAtIso: args['readThroughAt'] as String?,
        ),
      );
}
