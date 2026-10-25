import 'package:tentura_server/domain/use_case/constellation_layout_snapshot_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../mappers/constellation_gql_maps.dart';

final class QueryConstellationLayoutSnapshots extends GqlNodeBase {
  QueryConstellationLayoutSnapshots({
    ConstellationLayoutSnapshotCase? constellationLayoutSnapshotCase,
  }) : _case =
           constellationLayoutSnapshotCase ??
           GetIt.I<ConstellationLayoutSnapshotCase>();

  final ConstellationLayoutSnapshotCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationLayoutSnapshots,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationLayoutSnapshots =>
      GraphQLObjectField(
        'constellationLayoutSnapshots',
        GraphQLListType(
          gqlTypeConstellationLayoutSnapshot.nonNullable(),
        ).nonNullable(),
        resolve: (_, args) async => [
          for (final s in await _case.list(viewerId: getCredentials(args).sub))
            constellationLayoutSnapshotToGqlMap(s),
        ],
      );
}
