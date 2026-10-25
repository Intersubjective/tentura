import 'package:tentura_server/domain/use_case/constellation_layout_snapshot_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/constellation_gql_maps.dart';

final class MutationConstellationLayoutSnapshot extends GqlNodeBase {
  MutationConstellationLayoutSnapshot({
    ConstellationLayoutSnapshotCase? constellationLayoutSnapshotCase,
  }) : _case =
           constellationLayoutSnapshotCase ??
           GetIt.I<ConstellationLayoutSnapshotCase>();

  final ConstellationLayoutSnapshotCase _case;

  static final _kind = InputFieldInt(fieldName: 'kind');
  static final _reason = InputFieldInt(fieldName: 'reason');
  static final _snapshotId = InputFieldString(fieldName: 'snapshotId');
  static final _clientOpId = InputFieldString(fieldName: 'clientOpId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationLayoutSnapshotSave,
    constellationLayoutSnapshotRestore,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationLayoutSnapshotSave =>
      GraphQLObjectField(
        'constellationLayoutSnapshotSave',
        gqlTypeConstellationLayoutSnapshot.nonNullable(),
        arguments: [
          _kind.fieldNonNullable,
          _reason.fieldNonNullable,
          _clientOpId.field,
        ],
        resolve: (_, args) async => constellationLayoutSnapshotToGqlMap(
          await _case.save(
            viewerId: getCredentials(args).sub,
            kind: _kind.fromArgsNonNullable(args),
            reason: _reason.fromArgsNonNullable(args),
            clientOpId: _clientOpId.fromArgsNonNullable(args),
          ),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get constellationLayoutSnapshotRestore =>
      GraphQLObjectField(
        'constellationLayoutSnapshotRestore',
        gqlTypeConstellationLayoutSnapshot.nonNullable(),
        arguments: [_snapshotId.field, _clientOpId.field],
        resolve: (_, args) async => constellationLayoutSnapshotToGqlMap(
          await _case.restore(
            viewerId: getCredentials(args).sub,
            snapshotId: _snapshotId.fromArgsNonNullable(args),
            clientOpId: _clientOpId.fromArgsNonNullable(args),
          ),
        ),
      );
}
