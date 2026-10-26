import 'package:tentura_server/domain/use_case/constellation_tag_magnet_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationConstellationTagMagnet extends GqlNodeBase {
  MutationConstellationTagMagnet({
    ConstellationTagMagnetCase? constellationTagMagnetCase,
  }) : _case =
           constellationTagMagnetCase ?? GetIt.I<ConstellationTagMagnetCase>();

  final ConstellationTagMagnetCase _case;

  static final _tagId = InputFieldString(fieldName: 'tagId');
  static final _xUnits = InputFieldFloat(fieldName: 'xUnits');
  static final _yUnits = InputFieldFloat(fieldName: 'yUnits');
  static final _clientOpId = InputFieldString(fieldName: 'clientOpId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationTagMagnetUpsert,
    constellationTagMagnetRemove,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationTagMagnetUpsert =>
      GraphQLObjectField(
        'constellationTagMagnetUpsert',
        gqlTypeConstellationTagMagnet.nonNullable(),
        arguments: [
          _tagId.field,
          _xUnits.fieldNonNullable,
          _yUnits.fieldNonNullable,
          _clientOpId.field,
        ],
        resolve: (_, args) async => (await _case.upsert(
          viewerId: getCredentials(args).sub,
          tagId: _tagId.fromArgsNonNullable(args),
          xUnits: _xUnits.fromArgsNonNullable(args),
          yUnits: _yUnits.fromArgsNonNullable(args),
          clientOpId: _clientOpId.fromArgsNonNullable(args),
        )).toJson(),
      );

  GraphQLObjectField<dynamic, dynamic> get constellationTagMagnetRemove =>
      GraphQLObjectField(
        'constellationTagMagnetRemove',
        graphQLBoolean.nonNullable(),
        arguments: [_tagId.field, _clientOpId.field],
        resolve: (_, args) async {
          await _case.remove(
            viewerId: getCredentials(args).sub,
            tagId: _tagId.fromArgsNonNullable(args),
            clientOpId: _clientOpId.fromArgsNonNullable(args),
          );
          return true;
        },
      );
}
