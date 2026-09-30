import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';

import '../closure_gql_errors.dart';
import '../custom_types.dart';
import '../gql_nodel_base.dart';

/// `[ClosureSplitEntryInput!]` that also accepts an explicit `null` (delete
/// the custom split) on executors without the null-safe argument coercion of
/// the production schema. Null and `[]` both mean "no custom split".
final class _NullableSplitType
    extends GraphQLListType<Map<String, dynamic>, Map<String, dynamic>> {
  _NullableSplitType() : super(gqlInputClosureSplitEntry.nonNullable());

  @override
  GraphQLType<List<Map<String, dynamic>>, List<Map<String, dynamic>>>
  coerceToInputObject() => this;

  @override
  ValidationResult<List<Map<String, dynamic>>> validate(
    String key,
    List<dynamic>? input,
  ) => super.validate(key, input ?? const []);

  @override
  List<Map<String, dynamic>> deserialize(List<dynamic>? serialized) =>
      serialized == null
      ? const []
      : super.deserialize(serialized);
}

final class MutationClosure extends GqlNodeBase {
  MutationClosure({ClosureCase? closureCase})
    : _closureCase = closureCase ?? GetIt.I<ClosureCase>();

  final ClosureCase _closureCase;

  final _beaconId = GraphQLFieldInput(
    'beaconId',
    graphQLString.nonNullable(),
  );

  final _expectedEpoch = GraphQLFieldInput(
    'expectedEpoch',
    graphQLInt.nonNullable(),
  );

  final _helperId = GraphQLFieldInput(
    'helperId',
    graphQLString.nonNullable(),
  );

  final _targetId = GraphQLFieldInput(
    'targetId',
    graphQLString.nonNullable(),
  );

  final _on = GraphQLFieldInput('on', graphQLBoolean.nonNullable());

  final _body = GraphQLFieldInput('body', graphQLString.nonNullable());

  final _outcome = GraphQLFieldInput<String?, String?>(
    'outcome',
    gqlEnumClosureOutcome,
    defaultsToNull: true,
  );

  final _split = GraphQLFieldInput<List<Map<String, dynamic>>, dynamic>(
    'split',
    _NullableSplitType(),
    defaultsToNull: true,
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconClose,
    beaconCloseNow,
    beaconExtendClosure,
    beaconReopen,
    closureSaveOutcome,
    closureSaveAuthorSplit,
    closureToggleSupport,
    closureDone,
    closureSkip,
    closureSetMark,
    closureSaveStory,
  ];

  String _beacon(Map<String, dynamic> args) => args[_beaconId.name]! as String;

  int _epoch(Map<String, dynamic> args) => args[_expectedEpoch.name]! as int;

  GraphQLObjectField<dynamic, dynamic> _ok(
    String name,
    List<GraphQLFieldInput<dynamic, dynamic>> arguments,
    Future<void> Function(Map<String, dynamic> args, String userId) run,
  ) => GraphQLObjectField(
    name,
    graphQLBoolean.nonNullable(),
    arguments: arguments,
    resolve: (_, args) => mapClosureErrors(() async {
      await run(args, getCredentials(args).sub);
      return true;
    }),
  );

  GraphQLObjectField<dynamic, dynamic> get beaconClose => _ok(
    'beaconClose',
    [_beaconId],
    (args, userId) =>
        _closureCase.close(authorId: userId, beaconId: _beacon(args)),
  );

  GraphQLObjectField<dynamic, dynamic> get beaconCloseNow => _ok(
    'beaconCloseNow',
    [_beaconId, _expectedEpoch],
    (args, userId) => _closureCase.closeNow(
      authorId: userId,
      beaconId: _beacon(args),
      expectedEpoch: _epoch(args),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get beaconExtendClosure => _ok(
    'beaconExtendClosure',
    [_beaconId, _expectedEpoch],
    (args, userId) => _closureCase.extend(
      authorId: userId,
      beaconId: _beacon(args),
      expectedEpoch: _epoch(args),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get beaconReopen => _ok(
    'beaconReopen',
    [_beaconId, _expectedEpoch],
    (args, userId) => _closureCase.reopen(
      authorId: userId,
      beaconId: _beacon(args),
      expectedEpoch: _epoch(args),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get closureSaveOutcome => _ok(
    'closureSaveOutcome',
    [_beaconId, _expectedEpoch, _helperId, _outcome],
    (args, userId) => _closureCase.saveOutcome(
      authorId: userId,
      beaconId: _beacon(args),
      expectedEpoch: _epoch(args),
      helperId: args[_helperId.name]! as String,
      outcome: switch (args[_outcome.name] as String?) {
        'done' => ClosureOutcome.done,
        'notDone' => ClosureOutcome.notDone,
        'cantJudge' => ClosureOutcome.cantJudge,
        _ => null,
      },
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get closureSaveAuthorSplit => _ok(
    'closureSaveAuthorSplit',
    [_beaconId, _expectedEpoch, _split],
    (args, userId) {
      final raw = (args[_split.name] as List<dynamic>?) ?? const [];
      return _closureCase.saveAuthorSplit(
        authorId: userId,
        beaconId: _beacon(args),
        expectedEpoch: _epoch(args),
        split: raw.isEmpty
            ? null
            : {
                for (final e in raw.cast<Map<dynamic, dynamic>>())
                  e['helperId']! as String: e['pct']! as int,
              },
      );
    },
  );

  GraphQLObjectField<dynamic, dynamic> get closureToggleSupport =>
      GraphQLObjectField(
        'closureToggleSupport',
        gqlTypeClosureToggleResult.nonNullable(),
        arguments: [_beaconId, _expectedEpoch, _targetId, _on],
        resolve: (_, args) => mapClosureErrors(
          () => _closureCase
              .toggleSupport(
                voterId: getCredentials(args).sub,
                beaconId: _beacon(args),
                expectedEpoch: _epoch(args),
                targetId: args[_targetId.name]! as String,
                on: args[_on.name]! as bool,
              )
              .then((released) => {'released': released}),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get closureDone => _ok(
    'closureDone',
    [_beaconId, _expectedEpoch],
    (args, userId) => _closureCase.done(
      voterId: userId,
      beaconId: _beacon(args),
      expectedEpoch: _epoch(args),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get closureSkip => _ok(
    'closureSkip',
    [_beaconId, _expectedEpoch],
    (args, userId) => _closureCase.skip(
      voterId: userId,
      beaconId: _beacon(args),
      expectedEpoch: _epoch(args),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get closureSetMark => _ok(
    'closureSetMark',
    [_beaconId, _expectedEpoch, _targetId, _on],
    (args, userId) => _closureCase.setMark(
      userId: userId,
      beaconId: _beacon(args),
      expectedEpoch: _epoch(args),
      targetId: args[_targetId.name]! as String,
      on: args[_on.name]! as bool,
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get closureSaveStory => _ok(
    'closureSaveStory',
    [_beaconId, _expectedEpoch, _body],
    (args, userId) => _closureCase.saveStory(
      authorId: userId,
      beaconId: _beacon(args),
      expectedEpoch: _epoch(args),
      body: args[_body.name]! as String,
    ),
  );
}
