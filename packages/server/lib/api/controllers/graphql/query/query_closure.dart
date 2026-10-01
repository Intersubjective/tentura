import 'package:tentura_server/domain/closure/closure_view.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';

import '../closure_gql_errors.dart';
import '../custom_types.dart';
import '../gql_nodel_base.dart';

final class QueryClosure extends GqlNodeBase {
  QueryClosure({ClosureCase? closureCase})
    : _closureCase = closureCase ?? GetIt.I<ClosureCase>();

  final ClosureCase _closureCase;

  final _beaconId = GraphQLFieldInput(
    'beaconId',
    graphQLString.nonNullable(),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    closureState,
    closureResultForViewer,
  ];

  GraphQLObjectField<dynamic, dynamic> get closureState => GraphQLObjectField(
    'closureState',
    gqlTypeClosureState.nonNullable(),
    arguments: [_beaconId],
    resolve: (_, args) => mapClosureErrors(
      () => _closureCase
          .state(
            viewerId: getCredentials(args).sub,
            beaconId: args[_beaconId.name]! as String,
          )
          .then(_stateToMap),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get closureResultForViewer =>
      GraphQLObjectField(
        'closureResultForViewer',
        gqlTypeClosureResult,
        arguments: [_beaconId],
        resolve: (_, args) => mapClosureErrors(
          () => _closureCase
              .resultForViewer(
                viewerId: getCredentials(args).sub,
                beaconId: args[_beaconId.name]! as String,
              )
              .then(
                (r) => r == null
                    ? null
                    : {
                        'outcome': r.outcome.name,
                        'band': r.band.name,
                        'draftFlag': r.draftFlag.name,
                        'marks': r.marks,
                        'story': r.story,
                      },
              ),
        ),
      );

  static Map<String, Object?> _stateToMap(ClosureStateView s) => {
    'epoch': s.epoch,
    'status': s.status.dbValue,
    'role': s.role.name,
    'members': [
      for (final m in s.members)
        {
          'id': m.id,
          'notInRequest': m.notInRequest,
          'departure': m.departure,
        },
    ],
    'outcomes': s.outcomes?.entries
        .map((e) => {'helperId': e.key, 'outcome': e.value.name})
        .toList(),
    'split': s.split?.entries
        .map((e) => {'helperId': e.key, 'pct': e.value})
        .toList(),
    'mySupport': s.mySupport,
    'inCalcText': s.inCalcText,
    'myMarks': s.myMarks,
    'closesAt': s.closesAt.toUtc().toIso8601String(),
    'earlyCloseAt': s.earlyCloseAt?.toUtc().toIso8601String(),
    'canCloseNow': s.canCloseNow,
    'canReopen': s.canReopen,
    'extensionsUsed': s.extensionsUsed,
    'story': s.story,
  };
}
