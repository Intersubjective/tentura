import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/enums.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_availability.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/user_availability_case.dart';
import 'package:tentura_server/env.dart';

import '../../../domain/use_case/user_availability_case_test.dart'
    show InMemoryUserAvailabilityRepository;

/// Unwraps `nonNullable()`/list wrappers to the innermost named type.
String _baseTypeName(GraphQLType type) {
  var t = type;
  while (true) {
    if (t is GraphQLNonNullableType) {
      t = t.ofType;
    } else if (t is GraphQLListType) {
      t = t.ofType;
    } else {
      return t.name ?? t.toString();
    }
  }
}

bool _isNonNullable(GraphQLType type) => type is GraphQLNonNullableType;

GraphQL _availabilityGraphQL(MutationAvailability mutation) => GraphQL(
  GraphQLSchema(
    queryType: GraphQLObjectType('Query', 'Query root')
      ..fields.add(
        GraphQLObjectField(
          '_health',
          graphQLBoolean.nonNullable(),
          resolve: (_, __) => true,
        ),
      ),
    mutationType: GraphQLObjectType('Mutation', 'Mutation root')
      ..fields.addAll(mutation.all),
  ),
);

Future<Map<String, dynamic>> _executeDocument({
  required GraphQL graphQL,
  required String document,
  Map<String, dynamic> variables = const {},
  JwtEntity? jwt,
  String? operationName,
}) async {
  final result = await graphQL.parseAndExecute(
    document,
    operationName: operationName,
    variableValues: variables,
    globalVariables: {
      if (jwt != null) kGlobalInputQueryJwt: jwt,
    },
  );
  return result as Map<String, dynamic>;
}

void main() {
  const actor = 'Uavail-self';
  const auth = JwtEntity(sub: actor);

  late InMemoryUserAvailabilityRepository repo;
  late UserAvailabilityCase availabilityCase;
  late MutationAvailability mutation;
  late GraphQL graphQL;

  setUp(() {
    repo = InMemoryUserAvailabilityRepository();
    availabilityCase = UserAvailabilityCase(
      repo,
      env: Env(environment: Environment.test),
      logger: Logger('MutationAvailabilityTest'),
    );
    mutation = MutationAvailability(userAvailabilityCase: availabilityCase);
    graphQL = _availabilityGraphQL(mutation);
  });

  group('schema registration', () {
    test('MutationAvailability exposes the three availability mutations', () {
      final names = mutation.all.map((field) => field.name).toSet();
      expect(
        names,
        containsAll([
          'userAvailabilitySetLimited',
          'userAvailabilityPause',
          'userAvailabilityResume',
        ]),
      );
    });

    test('registered signatures are non-null Boolean with required args', () {
      final setLimited = mutation.all.singleWhere(
        (f) => f.name == 'userAvailabilitySetLimited',
      );
      final pause = mutation.all.singleWhere(
        (f) => f.name == 'userAvailabilityPause',
      );
      final resume = mutation.all.singleWhere(
        (f) => f.name == 'userAvailabilityResume',
      );

      expect(_isNonNullable(setLimited.type), isTrue);
      expect(_baseTypeName(setLimited.type), 'Boolean');
      expect(
        setLimited.inputs.singleWhere((i) => i.name == 'isLimited').type,
        isA<GraphQLNonNullableType>(),
      );

      expect(_isNonNullable(pause.type), isTrue);
      expect(_baseTypeName(pause.type), 'Boolean');
      expect(
        pause.inputs.singleWhere((i) => i.name == 'resumeOn').type,
        isA<GraphQLNonNullableType>(),
      );

      expect(_isNonNullable(resume.type), isTrue);
      expect(_baseTypeName(resume.type), 'Boolean');
      expect(resume.inputs, isEmpty);
    });
  });

  group('parseCalendarDate', () {
    test('accepts canonical YYYY-MM-DD and constructs UTC midnight', () {
      expect(
        parseCalendarDate('2026-08-18'),
        DateTime.utc(2026, 8, 18),
      );
    });

    test('rejects time-bearing and offset strings', () {
      for (final value in [
        '2026-08-18T00:00:00Z',
        '2026-08-18T00:00:00',
        '2026-08-18 00:00:00',
      ]) {
        expect(
          () => parseCalendarDate(value),
          throwsA(isA<ArgumentError>()),
          reason: value,
        );
      }
    });

    test('rejects non-canonical digit widths', () {
      for (final value in ['2026-8-18', '26-08-18', '2026-08-8']) {
        expect(
          () => parseCalendarDate(value),
          throwsA(isA<ArgumentError>()),
          reason: value,
        );
      }
    });

    test('rejects rollover calendar dates', () {
      expect(
        () => parseCalendarDate('2026-02-30'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => parseCalendarDate('2026-13-01'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('document execution', () {
    test('userAvailabilitySetLimited uses jwt.sub only and returns true', () async {
      final result = await _executeDocument(
        graphQL: graphQL,
        document: r'''
          mutation SetLimited($isLimited: Boolean!) {
            userAvailabilitySetLimited(isLimited: $isLimited)
          }
        ''',
        variables: const {'isLimited': true},
        jwt: auth,
        operationName: 'SetLimited',
      );

      expect(result['userAvailabilitySetLimited'], isTrue);
      expect(repo.setLimitedCalls, [(userId: actor, isLimited: true)]);
    });

    test('userAvailabilityPause parses resumeOn and delegates to the case', () async {
      final todayUtc = availabilityCase.todayUtcFrom(DateTime.timestamp());
      final resumeOn = DateTime.utc(todayUtc.year, todayUtc.month, todayUtc.day + 1);
      final resumeOnString =
          '${resumeOn.year.toString().padLeft(4, '0')}-'
          '${resumeOn.month.toString().padLeft(2, '0')}-'
          '${resumeOn.day.toString().padLeft(2, '0')}';

      final result = await _executeDocument(
        graphQL: graphQL,
        document: r'''
          mutation Pause($resumeOn: String!) {
            userAvailabilityPause(resumeOn: $resumeOn)
          }
        ''',
        variables: {'resumeOn': resumeOnString},
        jwt: auth,
        operationName: 'Pause',
      );

      expect(result['userAvailabilityPause'], isTrue);
      expect(repo.pauseCalls.single.userId, actor);
      expect(repo.pauseCalls.single.resumeOn, resumeOn);
    });

    test('userAvailabilityResume clears pause for jwt.sub and returns true', () async {
      final todayUtc = availabilityCase.todayUtcFrom(DateTime.timestamp());
      await availabilityCase.pause(
        userId: actor,
        resumeOn: DateTime.utc(todayUtc.year, todayUtc.month, todayUtc.day + 3),
      );

      final result = await _executeDocument(
        graphQL: graphQL,
        document: r'''
          mutation Resume {
            userAvailabilityResume
          }
        ''',
        jwt: auth,
      );

      expect(result['userAvailabilityResume'], isTrue);
      expect(repo.resumeCalls, [actor]);
    });

    test('missing JWT is rejected', () async {
      await expectLater(
        _executeDocument(
          graphQL: graphQL,
          document: r'''
            mutation Resume {
              userAvailabilityResume
            }
          ''',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('missing required isLimited is rejected by the schema', () async {
      await expectLater(
        _executeDocument(
          graphQL: graphQL,
          document: r'''
            mutation SetLimited {
              userAvailabilitySetLimited
            }
          ''',
          jwt: auth,
        ),
        throwsA(isA<GraphQLException>()),
      );
    });

    test('null resumeOn variable is rejected by the schema', () async {
      await expectLater(
        _executeDocument(
          graphQL: graphQL,
          document: r'''
            mutation Pause($resumeOn: String!) {
              userAvailabilityPause(resumeOn: $resumeOn)
            }
          ''',
          variables: const {'resumeOn': null},
          jwt: auth,
          operationName: 'Pause',
        ),
        throwsA(isA<GraphQLException>()),
      );
    });

    test('malformed resumeOn is rejected before repository writes', () async {
      await expectLater(
        _executeDocument(
          graphQL: graphQL,
          document: r'''
            mutation Pause($resumeOn: String!) {
              userAvailabilityPause(resumeOn: $resumeOn)
            }
          ''',
          variables: const {'resumeOn': '2026-02-30'},
          jwt: auth,
          operationName: 'Pause',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(repo.pauseCalls, isEmpty);
    });

    test('horizon edges are enforced by UserAvailabilityCase', () async {
      final todayUtc = availabilityCase.todayUtcFrom(DateTime.timestamp());
      final tomorrow = DateTime.utc(
        todayUtc.year,
        todayUtc.month,
        todayUtc.day + 1,
      );
      final maxAllowed = DateTime.utc(
        todayUtc.year,
        todayUtc.month,
        todayUtc.day + UserAvailabilityCase.maxPauseHorizonDays,
      );
      final tooFar = DateTime.utc(
        todayUtc.year,
        todayUtc.month,
        todayUtc.day + UserAvailabilityCase.maxPauseHorizonDays + 1,
      );

      String wire(DateTime date) =>
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

      await expectLater(
        _executeDocument(
          graphQL: graphQL,
          document: r'''
            mutation Pause($resumeOn: String!) {
              userAvailabilityPause(resumeOn: $resumeOn)
            }
          ''',
          variables: {'resumeOn': wire(todayUtc)},
          jwt: auth,
          operationName: 'Pause',
        ),
        throwsA(isA<ArgumentError>()),
      );

      final accepted = await _executeDocument(
        graphQL: graphQL,
        document: r'''
          mutation Pause($resumeOn: String!) {
            userAvailabilityPause(resumeOn: $resumeOn)
          }
        ''',
        variables: {'resumeOn': wire(maxAllowed)},
        jwt: auth,
        operationName: 'Pause',
      );
      expect(accepted['userAvailabilityPause'], isTrue);
      expect(repo.pauseCalls.last.resumeOn, maxAllowed);

      await expectLater(
        _executeDocument(
          graphQL: graphQL,
          document: r'''
            mutation Pause($resumeOn: String!) {
              userAvailabilityPause(resumeOn: $resumeOn)
            }
          ''',
          variables: {'resumeOn': wire(tooFar)},
          jwt: auth,
          operationName: 'Pause',
        ),
        throwsA(isA<ArgumentError>()),
      );

      repo.pauseCalls.clear();
      final acceptedTomorrow = await _executeDocument(
        graphQL: graphQL,
        document: r'''
          mutation Pause($resumeOn: String!) {
            userAvailabilityPause(resumeOn: $resumeOn)
          }
        ''',
        variables: {'resumeOn': wire(tomorrow)},
        jwt: auth,
        operationName: 'Pause',
      );
      expect(acceptedTomorrow['userAvailabilityPause'], isTrue);
      expect(repo.pauseCalls.single.resumeOn, tomorrow);
    });
  });

  group('limited and pause field independence', () {
    test('setLimited and pause touch independent columns', () async {
      final todayUtc = availabilityCase.todayUtcFrom(DateTime.timestamp());
      final resumeOn = DateTime.utc(todayUtc.year, todayUtc.month, todayUtc.day + 5);

      await availabilityCase.pause(userId: actor, resumeOn: resumeOn);
      await availabilityCase.setLimited(userId: actor, isLimited: true);
      await availabilityCase.setLimited(userId: actor, isLimited: false);

      final rowAfterClearLimited = repo.rowFor(actor)!;
      expect(rowAfterClearLimited.isLimited, isFalse);
      expect(rowAfterClearLimited.resumeOn, resumeOn);
      expect(
        rowAfterClearLimited.effectiveOn(todayUtc),
        AvailabilityView.paused,
      );

      await availabilityCase.setLimited(userId: actor, isLimited: true);
      await availabilityCase.resume(userId: actor);

      final rowAfterResume = repo.rowFor(actor)!;
      expect(rowAfterResume.isLimited, isTrue);
      expect(rowAfterResume.resumeOn, isNull);
      expect(rowAfterResume.effectiveOn(todayUtc), AvailabilityView.limited);
    });
  });

  group('resolver seam', () {
    test('setLimited ignores extra args and uses jwt.sub only', () async {
      final field = mutation.all.singleWhere(
        (f) => f.name == 'userAvailabilitySetLimited',
      );
      expect(
        await field.resolve!(null, {
          kGlobalInputQueryJwt: auth,
          'isLimited': false,
          'userId': 'U-attacker',
        }),
        isTrue,
      );
      expect(repo.setLimitedCalls, [(userId: actor, isLimited: false)]);
    });

    test('pause resolver requires authentication', () {
      final field = mutation.all.singleWhere(
        (f) => f.name == 'userAvailabilityPause',
      );
      expect(
        () => field.resolve!(null, {'resumeOn': '2026-08-18'}),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
