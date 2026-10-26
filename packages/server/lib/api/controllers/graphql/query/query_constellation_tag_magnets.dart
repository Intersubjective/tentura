import 'package:tentura_server/domain/use_case/constellation_tag_magnet_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

final class QueryConstellationTagMagnets extends GqlNodeBase {
  QueryConstellationTagMagnets({
    ConstellationTagMagnetCase? constellationTagMagnetCase,
  }) : _case =
           constellationTagMagnetCase ?? GetIt.I<ConstellationTagMagnetCase>();

  final ConstellationTagMagnetCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationTagMagnets,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationTagMagnets =>
      GraphQLObjectField(
        'constellationTagMagnets',
        GraphQLListType(
          gqlTypeConstellationTagMagnet.nonNullable(),
        ).nonNullable(),
        resolve: (_, args) async => [
          for (final m in await _case.list(viewerId: getCredentials(args).sub))
            m.toJson(),
        ],
      );
}
