import 'package:tentura_server/domain/port/beacon_child_create_port.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_v2_dto_maps.dart';

final class MutationBeaconHierarchy extends GqlNodeBase {
  MutationBeaconHierarchy({BeaconChildCreatePort? childCreatePort})
    : _childCreatePort = childCreatePort ?? GetIt.I<BeaconChildCreatePort>();

  final BeaconChildCreatePort _childCreatePort;

  final _parentBeaconId = InputFieldString(fieldName: 'parentBeaconId');
  final _sourceMessageId = InputFieldString(fieldName: 'sourceMessageId');
  final _clientCommandId = InputFieldString(fieldName: 'clientCommandId');
  final _startAt = InputFieldDatetime(fieldName: 'startAt');
  final _endAt = InputFieldDatetime(fieldName: 'endAt');
  final _tags = InputFieldString(fieldName: 'tags');
  final _needs = InputFieldString(fieldName: 'needs');
  final _addressLabel = InputFieldString(fieldName: 'addressLabel');
  final _draft = InputFieldBool(fieldName: 'draft');
  final _primaryNeedSlug = InputFieldString(fieldName: 'primaryNeedSlug');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [beaconChildCreate];

  GraphQLObjectField<dynamic, dynamic> get beaconChildCreate =>
      GraphQLObjectField(
        'beaconChildCreate',
        gqlTypeBeaconChildCreateResult.nonNullable(),
        arguments: [
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
          _draft.fieldNullable,
          _parentBeaconId.field,
          _sourceMessageId.fieldNullable,
          _clientCommandId.field,
        ],
        resolve: (_, args) async {
          final actorUserId = getCredentials(args).sub;
          final result = await _childCreatePort.createChild(
            actorUserId: actorUserId,
            parentBeaconId: _parentBeaconId.fromArgsNonNullable(args),
            sourceMessageId: _sourceMessageId.fromArgs(args),
            clientCommandId: _clientCommandId.fromArgsNonNullable(args),
            title: InputFieldBeaconTitle.fromArgsNonNullable(args),
            description: InputFieldDescription.fromArgs(args),
            context: InputFieldContext.fromArgs(args),
            tags: _tags.fromArgs(args),
            needs: _needs.fromArgs(args),
            primaryNeedSlug: _primaryNeedSlug.fromArgs(args),
            primaryNeedSlugProvided: args.containsKey('primaryNeedSlug'),
            startAt: _startAt.fromArgs(args),
            endAt: _endAt.fromArgs(args),
            coordinates: InputFieldCoordinates.fromArgs(args),
            addressLabel: _addressLabel.fromArgs(args),
            draft: _draft.fromArgs(args) ?? false,
          );
          return beaconChildCreateResultToGqlMap(result);
        },
      );
}
