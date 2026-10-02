import 'dart:convert';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_closure.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_closure.dart';
import 'package:tentura_server/domain/closure/closure_band.dart';
import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_exception.dart';
import 'package:tentura_server/domain/closure/closure_receipt_payload.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_receipts_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';
import 'package:tentura_server/env.dart';

import '../support/beacon_lifecycle_effects_test_support.dart';
import '../support/fake_beacon_hierarchy_repository.dart';

// A16 (Arch §7): GraphQL V2 closure API.
//
// Contract assumed by these tests (per the unit brief):
//  * `QueryClosure({ClosureCase? closureCase})` / `MutationClosure({...})`
//    expose `.all` like the other query/mutation classes;
//  * reads go through `ClosureCase` over the existing ports, never through a
//    full-entity serialisation; the viewer comes from the JWT only;
//  * not-found is `IdNotFoundException` (code of `GeneralExceptionCode`),
//    identical for outsider and blocked member so roles do not leak.

const _beaconId = 'Bclgqbeacon001';
const _authorId = 'Uclgqauthor001';
const _voterId = 'Uclgqvoter0001';
const _otherVoterId = 'Uclgqvoter0002';
const _leaverId = 'Uclgqleaver001';
const _removedId = 'Uclgqremoved01';
const _blockedId = 'Uclgqblocked01';
const _outsiderId = 'Uclgqoutsider1';

const _stateFields = {
  'epoch',
  'status',
  'role',
  'members',
  'outcomes',
  'split',
  'mySupport',
  'inCalcText',
  'myMarks',
  'closesAt',
  'earlyCloseAt',
  'canCloseNow',
  'canReopen',
  'extensionsUsed',
  'story',
};

const _memberFields = {
  'id',
  'displayName',
  'avatarId',
  'helpTypes',
  'offerText',
  'notInRequest',
  'departure',
};

const _forbiddenKey = 'share|helped|pct';

void main() {
  group('closure schema contract', () {
    test(
      'ClosureResult has exactly outcome, band, draftFlag, marks, story',
      () {
        final type = _objectType('ClosureResult');
        expect(
          type.fields.map((f) => f.name).toSet(),
          {'outcome', 'band', 'draftFlag', 'marks', 'story'},
        );
        expect(type.fields, hasLength(5));
      },
    );

    test('ClosureResult is reachable through introspection', () async {
      final result = await _graph().parseAndExecute(
        '{ __type(name: "ClosureResult") { fields { name } } }',
      );
      final names = ((result! as Map)['__type'] as Map)['fields'] as List;
      expect(
        names.map((f) => (f as Map)['name']).toSet(),
        {'outcome', 'band', 'draftFlag', 'marks', 'story'},
      );
    });

    test('closure types, enums and roles are registered custom types', () {
      final names = customTypes.map((t) => t.name).toSet();
      expect(
        names,
        containsAll(<String>[
          'ClosureState',
          'ClosureMember',
          'ClosureResult',
          'ClosureOutcome',
          'ClosureBand',
          'ClosureDraftFlag',
          'ClosureRole',
        ]),
      );
      GraphQLEnumType<dynamic> enumType(String name) =>
          customTypes.whereType<GraphQLEnumType<dynamic>>().singleWhere(
            (t) => t.name == name,
          );
      expect(
        enumType('ClosureBand').values.map((v) => v.name).toSet(),
        {'raised', 'asIfSilent', 'lowered', 'none'},
      );
      expect(
        enumType('ClosureRole').values.map((v) => v.name).toSet(),
        {'author', 'voter', 'member'},
      );
      expect(
        enumType('ClosureOutcome').values.map((v) => v.name).toSet(),
        {'done', 'notDone', 'cantJudge'},
      );
    });

    test('no other user numeric share/helped/pct field in closure schema', () {
      final names = <String>[];
      for (final t in customTypes.whereType<GraphQLObjectType>().where(
        (t) => t.name.startsWith('Closure'),
      )) {
        for (final f in t.fields) {
          names.add('${t.name}.${f.name}');
        }
      }
      expect(names, isNotEmpty);
      final bad = names.where(
        (n) =>
            RegExp(_forbiddenKey, caseSensitive: false).hasMatch(n) &&
            n != 'ClosureState.split' &&
            !n.startsWith('ClosureSplit'),
      );
      expect(bad, isEmpty);
      // ClosureMember is visible to every role: never a split or share value.
      expect(
        _objectType('ClosureMember').fields.map((f) => f.name),
        isNot(contains('split')),
      );
    });

    test('ClosureState declares the allowlisted fields', () {
      expect(
        _objectType('ClosureState').fields.map((f) => f.name),
        containsAll(<String>[
          'members',
          'split',
          'story',
          'canCloseNow',
          'canReopen',
          'earlyCloseAt',
        ]),
      );
    });

    test('ClosureState exposes extensionsUsed as a nullable Int', () {
      final field = _objectType(
        'ClosureState',
      ).fields.where((f) => f.name == 'extensionsUsed');
      expect(field, hasLength(1));
      // Author-only like canReopen: null for the other roles, so not `Int!`.
      expect(field.single.type, same(graphQLInt));
    });

    test('query and mutation tables match Arch §7', () {
      final queries = QueryClosure(closureCase: _closureCase(_Fixture())).all;
      expect(
        queries.map((f) => f.name).toSet(),
        {'closureState', 'closureResultForViewer'},
      );
      final mutations = MutationClosure(
        closureCase: _closureCase(_Fixture()),
      ).all;
      expect(
        mutations.map((f) => f.name),
        containsAll(<String>[
          'beaconClose',
          'beaconCloseNow',
          'beaconExtendClosure',
          'beaconReopen',
          'closureSaveOutcome',
          'closureSaveAuthorSplit',
          'closureToggleSupport',
          'closureDone',
          'closureSkip',
          'closureSetMark',
          'closureSaveStory',
        ]),
      );
      for (final name in [
        'beaconCloseNow',
        'beaconExtendClosure',
        'beaconReopen',
        'closureSaveOutcome',
        'closureSaveAuthorSplit',
        'closureToggleSupport',
        'closureDone',
        'closureSkip',
        'closureSetMark',
        'closureSaveStory',
      ]) {
        expect(
          mutations
              .singleWhere((f) => f.name == name)
              .inputs
              .map((i) => i.name),
          contains('expectedEpoch'),
          reason: '$name must carry expectedEpoch',
        );
      }
      expect(
        mutations
            .singleWhere((f) => f.name == 'beaconClose')
            .inputs
            .map((i) => i.name),
        isNot(contains('expectedEpoch')),
      );
    });

    test('ClosureState and ClosureMember fields are exactly the allowlist', () {
      expect(
        _objectType('ClosureState').fields.map((f) => f.name).toSet(),
        _stateFields,
      );
      expect(
        _objectType('ClosureMember').fields.map((f) => f.name).toSet(),
        _memberFields,
      );
    });
  });

  group('closureState role matrix (serialized JSON)', () {
    late _Fixture fx;
    late GraphQL graph;

    setUp(() {
      fx = _Fixture();
      graph = _graph(fx);
    });

    Future<Map<String, dynamic>> state(String viewer, {String? forged}) => _run(
      graph,
      'closureState',
      viewer,
      args: 'beaconId: "${forged ?? _beaconId}"',
      selection: _selection(_objectType('ClosureState')),
    );

    test(
      'author sees own split, canCloseNow, canReopen and no commits',
      () async {
        final r = await state(_authorId);
        expect(r['errors'], isNull, reason: '${r['errors']}');
        final s = r['closureState'] as Map<String, dynamic>;
        expect(s['split'], isNotNull);
        expect(s['canCloseNow'], isA<bool>());
        expect(s['canReopen'], isA<bool>());
        // The author learns only `canCloseNow`, never who committed.
        final leaked = _populated(s).where(
          (e) =>
              RegExp('commit|support', caseSensitive: false).hasMatch(e.key) &&
              e.key != 'canCloseNow',
        );
        expect(leaked, isEmpty);
        expect(jsonEncode(s), isNot(contains('committedAt')));
      },
    );

    test(
      'active voter: no split/outcomes/author-only flags, no peer data',
      () async {
        final r = await state(_voterId);
        expect(r['errors'], isNull, reason: '${r['errors']}');
        final s = r['closureState'] as Map<String, dynamic>;
        _expectNoAuthorOnlyFields(s);
        expect(s['earlyCloseAt'], anyOf(isNull, isA<String>()));
        // Other voters' supports and commits (seeded for the other voter) must
        // never reach this viewer.
        for (final e in _populated(s).where(
          (e) => RegExp('support|commit|vote', caseSensitive: false).hasMatch(
            e.key,
          ),
        )) {
          expect(jsonEncode(e.value), isNot(contains(_leaverId)));
          expect(jsonEncode(e.value), isNot(contains(_otherVoterId)));
        }
        _expectNoForbiddenKeys(s);
      },
    );

    for (final (label, viewer) in [
      ('voluntary leaver', _leaverId),
      ('removed member', _removedId),
    ]) {
      test('$label: member view without author-only or voting data', () async {
        final r = await state(viewer);
        expect(r['errors'], isNull, reason: '${r['errors']}');
        final s = r['closureState'] as Map<String, dynamic>;
        _expectNoAuthorOnlyFields(s);
        expect(
          _populated(s).where(
            (e) => RegExp('support|commit', caseSensitive: false).hasMatch(
              e.key,
            ),
          ),
          isEmpty,
        );
        _expectNoForbiddenKeys(s);
      });
    }

    test('outsider gets not found for closureState', () async {
      _expectNotFound(await state(_outsiderId));
    });

    test('blocked member gets not found for closureState', () async {
      _expectNotFound(await state(_blockedId));
    });

    test('forged beaconId gets not found for every role', () async {
      for (final viewer in [_authorId, _voterId, _leaverId, _outsiderId]) {
        _expectNotFound(await state(viewer, forged: 'Bforged0000001'));
      }
    });

    test(
      'closureState takes only beaconId; a forged expectedEpoch is ignored',
      () async {
        final args = QueryClosure(closureCase: _closureCase(fx)).all
            .singleWhere((f) => f.name == 'closureState')
            .inputs
            .map((i) => i.name)
            .toList();
        expect(args, ['beaconId']);
        final selection = _selection(_objectType('ClosureState'));
        for (final viewer in [_authorId, _voterId, _leaverId]) {
          final base = await _run(
            graph,
            'closureState',
            viewer,
            args: 'beaconId: "$_beaconId"',
            selection: selection,
          );
          final forged = await _run(
            graph,
            'closureState',
            viewer,
            args: 'beaconId: "$_beaconId", expectedEpoch: 99',
            selection: selection,
          );
          expect(base['errors'], isNull, reason: '${base['errors']}');
          expect(jsonEncode(forged), jsonEncode(base));
        }
        for (final viewer in [_outsiderId, _blockedId]) {
          _expectNotFound(
            await _run(
              graph,
              'closureState',
              viewer,
              args: 'beaconId: "$_beaconId", expectedEpoch: 99',
              selection: selection,
            ),
          );
        }
      },
    );

    test(
      'viewer comes from the JWT; forged userId/viewerId args are ignored',
      () async {
        final r = await _run(
          graph,
          'closureState',
          _outsiderId,
          args:
              'beaconId: "$_beaconId", userId: "$_authorId", viewerId: "$_authorId"',
          selection: _selection(_objectType('ClosureState')),
        );
        _expectNotFound(r);
      },
    );
  });

  group('closureState extensionsUsed (serialized JSON)', () {
    Future<Map<String, dynamic>> state(
      String viewer,
      int extensionsUsed,
    ) async {
      final r = await _run(
        _graph(_Fixture(extensionsUsed: extensionsUsed)),
        'closureState',
        viewer,
        args: 'beaconId: "$_beaconId"',
        selection: _selection(_objectType('ClosureState')),
      );
      expect(r['errors'], isNull, reason: '${r['errors']}');
      return r['closureState'] as Map<String, dynamic>;
    }

    test('author sees the live epoch extension count', () async {
      for (final used in [0, 1, 2]) {
        final s = await state(_authorId, used);
        expect(s['extensionsUsed'], used, reason: 'extensionsUsed=$used');
      }
    });

    for (final (label, viewer) in [
      ('active voter', _voterId),
      ('voluntary leaver', _leaverId),
    ]) {
      test('$label does not get extensionsUsed', () async {
        final s = await state(viewer, 2);
        expect(s.containsKey('extensionsUsed'), isTrue);
        expect(s['extensionsUsed'], isNull);
      });
    }
  });

  group('closureState exact per-role shape (serialized JSON)', () {
    late GraphQL graph;

    setUp(() => graph = _graph(_Fixture()));

    Future<Map<String, dynamic>> state(String viewer) async {
      final r = await _run(
        graph,
        'closureState',
        viewer,
        args: 'beaconId: "$_beaconId"',
        selection: _selection(_objectType('ClosureState')),
      );
      expect(r['errors'], isNull, reason: '${r['errors']}');
      return r['closureState'] as Map<String, dynamic>;
    }

    void expectShape(
      Map<String, dynamic> s, {
      required String role,
      required Set<String> allowed,
      required Set<String> required,
    }) {
      expect(s.keys.toSet(), _stateFields, reason: 'selection is complete');
      final present = _nonNullKeys(s);
      expect(
        present.difference(allowed),
        isEmpty,
        reason: 'populated but not allowed for $role',
      );
      expect(
        present.containsAll(required),
        isTrue,
        reason: 'missing for $role: ${required.difference(present)}',
      );
      expect('${s['role']}', role);
    }

    void expectMemberKeys(
      Map<String, dynamic> s, {
      required bool authorDetail,
    }) {
      final members = s['members'] as List<dynamic>;
      expect(
        members.map((m) => (m as Map)['id']).toSet(),
        containsAll(<String>[_voterId, _otherVoterId, _leaverId, _removedId]),
      );
      for (final m in members.cast<Map<String, dynamic>>()) {
        expect(m.keys.toSet(), _memberFields);
        expect(m['notInRequest'], isA<bool>());
        if (!authorDetail) {
          expect(
            m['departure'],
            isNull,
            reason: 'departure detail is author-only',
          );
        }
      }
      if (authorDetail) {
        final byId = {
          for (final m in members.cast<Map<String, dynamic>>())
            m['id'] as String: m,
        };
        expect(byId[_leaverId]!['departure'], isNotNull);
        expect(byId[_removedId]!['departure'], isNotNull);
        expect(byId[_voterId]!['departure'], isNull);
      }
    }

    test(
      'author: allowlisted keys only, own split, numbers are split only',
      () async {
        final s = await state(_authorId);
        expectShape(
          s,
          role: 'author',
          allowed: {
            'epoch',
            'status',
            'role',
            'members',
            'outcomes',
            'split',
            'myMarks',
            'closesAt',
            'earlyCloseAt',
            'canCloseNow',
            'canReopen',
            'extensionsUsed',
            'story',
          },
          required: {
            'role',
            'members',
            'split',
            'closesAt',
            'canCloseNow',
            'canReopen',
            'extensionsUsed',
          },
        );
        expectMemberKeys(s, authorDetail: true);
        final nums = _numbers(s);
        expect(nums, containsAll(<num>[60, 40]));
        expect(
          nums.every((n) => n is int),
          isTrue,
          reason: 'no fractional share',
        );
        expect(jsonEncode(s), isNot(contains('0.42')));
        // Only `canCloseNow`; never who committed or supported.
        expect(jsonEncode(s), isNot(contains('committedAt')));
        expect(s['mySupport'], anyOf(isNull, isEmpty));
      },
    );

    test(
      'active voter: allowlisted keys only, own marks only, no numbers',
      () async {
        final s = await state(_voterId);
        expectShape(
          s,
          role: 'voter',
          allowed: {
            'epoch',
            'status',
            'role',
            'members',
            'mySupport',
            'inCalcText',
            'myMarks',
            'closesAt',
            'earlyCloseAt',
          },
          required: {'role', 'members', 'myMarks', 'closesAt'},
        );
        expectMemberKeys(s, authorDetail: false);
        // myMarks is the viewer's own target ids: the other voter marked this
        // viewer, which must not surface.
        final marks = jsonEncode(s['myMarks']);
        expect(marks, contains(_otherVoterId));
        expect(marks, isNot(contains(_voterId)));
        // Own support is present; the peer voter's support and commit are
        // not, whatever the field is called.
        final mySupport = jsonEncode(s['mySupport']);
        expect(mySupport, contains(_removedId));
        expect(mySupport, isNot(contains(_leaverId)));
        final rest = Map<String, dynamic>.of(s)..remove('members');
        expect(jsonEncode(rest), isNot(contains(_leaverId)));
        final wire = jsonEncode(s);
        for (final peer in ['2026-09-02T07:08:09', '2026-09-03T04:05:06']) {
          expect(wire, isNot(contains(peer)), reason: 'peer data leaked');
        }
        expect(_numbers(s).every((n) => const {0, 1, 2}.contains(n)), isTrue);
        _expectNoForbiddenKeys(s);
      },
    );

    for (final (label, viewer) in [
      ('voluntary leaver', _leaverId),
      ('removed member', _removedId),
    ]) {
      test(
        '$label: allowlisted keys only, no voting data, no numbers',
        () async {
          final s = await state(viewer);
          expectShape(
            s,
            role: 'member',
            allowed: {
              'epoch',
              'status',
              'role',
              'members',
              'myMarks',
              'closesAt',
            },
            required: {'role', 'members', 'closesAt'},
          );
          expectMemberKeys(s, authorDetail: false);
          expect(s['myMarks'], anyOf(isNull, isEmpty));
          expect(_numbers(s).every((n) => const {0, 1, 2}.contains(n)), isTrue);
          _expectNoForbiddenKeys(s);
        },
      );
    }
  });

  group('closureResultForViewer role matrix (serialized JSON)', () {
    late _Fixture fx;
    late GraphQL graph;

    setUp(() {
      fx = _Fixture(finalized: true);
      graph = _graph(fx);
    });

    Future<Map<String, dynamic>> result(String viewer) => _run(
      graph,
      'closureResultForViewer',
      viewer,
      args: 'beaconId: "$_beaconId"',
      selection: _selection(_objectType('ClosureResult')),
    );

    for (final (label, viewer) in [
      ('active voter', _voterId),
      ('voluntary leaver', _leaverId),
      ('removed member', _removedId),
      ('blocked member', _blockedId),
    ]) {
      test(
        '$label gets only own outcome, band, draftFlag, marks, story',
        () async {
          final r = await result(viewer);
          expect(r['errors'], isNull, reason: '${r['errors']}');
          final res = r['closureResultForViewer'] as Map<String, dynamic>;
          expect(
            res.keys.toSet(),
            {'outcome', 'band', 'draftFlag', 'marks', 'story'},
          );
          _expectNoForbiddenKeys(res);
          // No numeric share/helped/pct: the seeded helped=0.42 never leaves.
          expect(_numbers(res), isEmpty);
          expect(jsonEncode(res), isNot(contains('0.42')));
          expect('${res['outcome']}', 'done');
          expect('${res['band']}', 'raised');
          expect('${res['draftFlag']}', 'none');
          expect(res['story'], 'A story');
          // Marks are the viewer's own target ids only.
          final marks = jsonEncode(res['marks']);
          expect(marks, isNot(contains(_leaverId)));
          if (viewer == _voterId) {
            expect(marks, contains(_otherVoterId));
            expect(marks, isNot(contains(_voterId)));
          } else {
            expect(res['marks'], anyOf(isNull, isEmpty));
          }
        },
      );
    }

    test(
      'the request author is not a member: not found (member only)',
      () async {
        _expectNotFound(await result(_authorId));
      },
    );

    test('outsider gets not found for closureResultForViewer', () async {
      _expectNotFound(await result(_outsiderId));
    });

    test('forged beaconId gets not found', () async {
      final r = await _run(
        graph,
        'closureResultForViewer',
        _voterId,
        args: 'beaconId: "Bforged0000001"',
        selection: _selection(_objectType('ClosureResult')),
      );
      _expectNotFound(r);
    });
  });

  group('closure mutations map ClosureException to extensions.code', () {
    late GraphQL graph;
    late List<GraphQLObjectField<dynamic, dynamic>> fields;

    setUp(() {
      final c = _closureCase(_Fixture());
      fields = MutationClosure(closureCase: c).all;
      graph = _graph(_Fixture());
    });

    String codeOf(ClosureExceptionCode c) =>
        '${ClosureExceptionCodes(c).codeNumber}';

    Future<Map<String, dynamic>> call(
      String name,
      String viewer,
      int epoch,
    ) {
      const extra = {
        'closureSaveOutcome': ', helperId: "$_voterId", outcome: done',
        'closureSaveAuthorSplit': ', split: null',
        'closureToggleSupport': ', targetId: "$_otherVoterId", on: true',
        'closureSetMark': ', targetId: "$_otherVoterId", on: true',
        'closureSaveStory': ', body: "story"',
      };
      var sel = '';
      var t = fields.singleWhere((f) => f.name == name).type;
      while (t is GraphQLNonNullableType || t is GraphQLListType) {
        t = t is GraphQLNonNullableType
            ? t.ofType
            : (t as GraphQLListType).ofType;
      }
      if (t is GraphQLObjectType) sel = ' { ${_selection(t)} }';
      return _exec(
        graph,
        'mutation { $name(beaconId: "$_beaconId", expectedEpoch: $epoch'
        '${extra[name] ?? ''})$sel }',
        viewer,
      );
    }

    String firstCode(Map<String, dynamic> r) {
      final errors = r['errors'] as List<dynamic>?;
      expect(errors, isNotNull, reason: '$r');
      return '${((errors!.first as Map)['extensions'] as Map)['code']}';
    }

    const epochMutations = [
      'beaconCloseNow',
      'beaconExtendClosure',
      'beaconReopen',
      'closureSaveOutcome',
      'closureSaveAuthorSplit',
      'closureToggleSupport',
      'closureDone',
      'closureSkip',
      'closureSetMark',
      'closureSaveStory',
    ];

    for (final name in epochMutations) {
      test('$name with a forged expectedEpoch is staleEpoch', () async {
        final viewer =
            name.startsWith('closureSave') || name.startsWith('beacon')
            ? _authorId
            : _voterId;
        expect(
          firstCode(await call(name, viewer, 99)),
          codeOf(ClosureExceptionCode.staleEpoch),
        );
      });
    }

    for (final name in [
      'beaconCloseNow',
      'beaconExtendClosure',
      'beaconReopen',
      'closureSaveOutcome',
      'closureSaveAuthorSplit',
      'closureSaveStory',
    ]) {
      test('$name by a voter is notAuthor', () async {
        expect(
          firstCode(await call(name, _voterId, 1)),
          codeOf(ClosureExceptionCode.notAuthor),
        );
      });
    }

    for (final name in ['closureToggleSupport', 'closureDone', 'closureSkip']) {
      test('$name by the author is notVoter', () async {
        expect(
          firstCode(await call(name, _authorId, 1)),
          codeOf(ClosureExceptionCode.notVoter),
        );
      });
    }

    test('closureSetMark by an outsider is notMember', () async {
      expect(
        firstCode(await call('closureSetMark', _outsiderId, 1)),
        codeOf(ClosureExceptionCode.notMember),
      );
    });
  });

  group('closure receipt payloads (A17) carry codes only', () {
    void expectCodesOnly(Map<String, Object?> payload) {
      for (final v in payload.values) {
        expect(v, anyOf(isNull, isA<String>(), isA<bool>()));
      }
      expect(_numbers(payload), isEmpty);
    }

    test('finalized payload is outcome, band and draftFlag codes', () {
      final p = closureFinalizedReceiptPayload(
        outcome: ClosureOutcome.done,
        band: ClosureBand.raised,
        draftFlag: ClosureResultDraftFlag.lastEditNotCounted,
      );
      expect(p, {
        'outcome': 'done',
        'band': 'raised',
        'draftFlag': 'lastEditNotCounted',
      });
      expectCodesOnly(p);
    });

    test('opened and cancelled payloads contain no numbers', () {
      expectCodesOnly(closureOpenedReceiptPayload());
      expectCodesOnly(closureCancelledReceiptPayload());
    });
  });
}

// --- helpers ----------------------------------------------------------------

GraphQLObjectType _objectType(String name) => customTypes
    .whereType<GraphQLObjectType>()
    .singleWhere((t) => t.name == name, orElse: () => fail('missing $name'));

GraphQL _graph([_Fixture? fx]) {
  final c = _closureCase(fx ?? _Fixture());
  return GraphQL(
    GraphQLSchema(
      queryType: GraphQLObjectType('Query', null)
        ..fields.addAll(QueryClosure(closureCase: c).all),
      mutationType: GraphQLObjectType('Mutation', null)
        ..fields.addAll(MutationClosure(closureCase: c).all),
    ),
    customTypes: customTypes,
  );
}

/// Scalar/object selection generated from the declared type, so assertions
/// hold whatever the implementation names its fields.
String _selection(GraphQLObjectType type, [int depth = 0]) {
  final parts = <String>[];
  for (final f in type.fields) {
    var t = f.type;
    while (true) {
      if (t is GraphQLNonNullableType) {
        t = t.ofType;
      } else if (t is GraphQLListType) {
        t = t.ofType;
      } else {
        break;
      }
    }
    if (t is GraphQLObjectType) {
      if (depth < 2) parts.add('${f.name} { ${_selection(t, depth + 1)} }');
    } else {
      parts.add(f.name);
    }
  }
  return parts.join(' ');
}

Future<Map<String, dynamic>> _run(
  GraphQL graph,
  String field,
  String viewer, {
  required String args,
  required String selection,
}) => _exec(graph, '{ $field($args) { $selection } }', viewer);

Future<Map<String, dynamic>> _exec(
  GraphQL graph,
  String query,
  String viewer,
) async {
  try {
    final out = await graph.parseAndExecute(
      query,
      globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
    );
    return Map<String, dynamic>.from(out! as Map);
  } on GraphQLException catch (e) {
    return {
      'errors': e.errors.map((x) => x.toJson()).toList(),
    };
  }
}

void _expectNotFound(Map<String, dynamic> r) {
  final errors = r['errors'] as List<dynamic>?;
  expect(errors, isNotNull, reason: 'expected not found, got $r');
  expect(errors, isNotEmpty);
  final notFound = const IdNotFoundException().toMap['extensions']! as Map;
  final ext = (errors!.first as Map)['extensions'] as Map?;
  expect(ext?['code'], notFound['code']);
  for (final v in r.entries.where((e) => e.key != 'errors')) {
    expect(v.value, anyOf(isNull, isEmpty));
  }
}

Iterable<MapEntry<String, Object?>> _populated(Object? node) sync* {
  if (node is Map) {
    for (final e in node.entries) {
      final v = e.value;
      final empty = v == null || (v is Iterable && v.isEmpty) || v == false;
      if (!empty) yield MapEntry('${e.key}', v);
      yield* _populated(v);
    }
  } else if (node is Iterable) {
    for (final v in node) {
      yield* _populated(v);
    }
  }
}

void _expectNoAuthorOnlyFields(Map<String, dynamic> s) {
  final populated = _populated(s).map((e) => e.key).toSet();
  for (final k in ['split', 'outcomes', 'canCloseNow', 'canReopen']) {
    expect(populated, isNot(contains(k)), reason: '$k is author-only');
  }
}

void _expectNoForbiddenKeys(Object? json) {
  void walk(Object? n) {
    if (n is Map) {
      for (final e in n.entries) {
        expect(
          RegExp(_forbiddenKey, caseSensitive: false).hasMatch('${e.key}'),
          isFalse,
          reason: 'forbidden key ${e.key}',
        );
        walk(e.value);
      }
    } else if (n is Iterable) {
      n.forEach(walk);
    }
  }

  walk(json);
}

// --- fakes ------------------------------------------------------------------

ClosureCase _closureCase(_Fixture fx) => ClosureCase(
  unitOfWork: _PassThroughUow(),
  closureRepository: fx.repo,
  beaconRepository: fx.beacons,
  commitmentRepository: fx.commitments,
  helpOfferRepository: _NoHelpOffers(),
  hierarchyRepository: FakeBeaconHierarchyRepository(),
  lifecycleEffects: buildLifecycleEffectsCase(),
  attentionSystemSettlement: _NoSettlement(),
  receipts: _NoReceipts(),
  finalizer: _NoFinalizer(),
  env: Env(environment: Environment.test),
  logger: Logger('ClosureGraphqlTest'),
);

final _t0 = DateTime.utc(2026, 9, 1);
final _peerPressedAt = DateTime.utc(2026, 9, 2, 7, 8, 9);
final _peerCommittedAt = DateTime.utc(2026, 9, 3, 4, 5, 6);

final class _Fixture {
  _Fixture({this.finalized = false, this.extensionsUsed = 0}) {
    repo = _Repo(finalized: finalized, extensionsUsed: extensionsUsed);
    beacons = _Beacons();
    commitments = _Commitments();
  }

  final bool finalized;
  final int extensionsUsed;
  late final _Repo repo;
  late final _Beacons beacons;
  late final _Commitments commitments;
}

final class _Repo implements ClosureRepositoryPort {
  _Repo({required this.finalized, this.extensionsUsed = 0});

  final bool finalized;
  final int extensionsUsed;

  ClosureEpoch get _epoch => ClosureEpoch(
    beaconId: _beaconId,
    epoch: 1,
    status: finalized
        ? ClosureEpochStatus.finalized
        : ClosureEpochStatus.evaluating,
    openedAt: _t0,
    closesAt: _t0.add(const Duration(days: 7)),
    extensionsUsed: extensionsUsed,
    finalizedAt: finalized ? _t0.add(const Duration(days: 7)) : null,
  );

  @override
  Future<ClosureEpoch?> liveEpoch(String beaconId) async =>
      beaconId == _beaconId && !finalized ? _epoch : null;

  @override
  Future<ClosureEpoch?> latestEpoch(String beaconId) async =>
      beaconId == _beaconId ? _epoch : null;

  @override
  Future<int> maxEpoch(String beaconId) async => beaconId == _beaconId ? 1 : 0;

  @override
  Future<void> lockRequest(String beaconId) async {}

  @override
  Future<List<ClosureMemberRow>> members({
    required String beaconId,
    required int epoch,
  }) async => beaconId != _beaconId
      ? []
      : const [
          ClosureMemberRow(userId: _voterId, activeAtOpen: true),
          ClosureMemberRow(userId: _otherVoterId, activeAtOpen: true),
          ClosureMemberRow(
            userId: _leaverId,
            activeAtOpen: true,
            departure: Departure.voluntary,
          ),
          ClosureMemberRow(
            userId: _removedId,
            activeAtOpen: true,
            departure: Departure.removed,
          ),
          ClosureMemberRow(userId: _blockedId, activeAtOpen: true),
        ];

  @override
  Future<List<ClosureOutcomeRow>> outcomes(String beaconId) async => [
    ClosureOutcomeRow(
      helperId: _voterId,
      outcome: ClosureOutcome.done,
      updatedAt: _t0,
    ),
  ];

  @override
  Future<Map<String, int>> split(String beaconId) async => {
    _voterId: 60,
    _otherVoterId: 40,
  };

  @override
  Future<List<ClosureSupportRow>> supports({
    required String beaconId,
    required ClosureSupportVersion version,
  }) async => [
    // Peer voter's support: must never reach any other viewer.
    ClosureSupportRow(
      voterId: _otherVoterId,
      targetId: _leaverId,
      version: version,
      pressedAt: _peerPressedAt,
    ),
    // The active voter's own draft support (no committed version).
    if (version == ClosureSupportVersion.draft)
      ClosureSupportRow(
        voterId: _voterId,
        targetId: _removedId,
        version: version,
        pressedAt: _t0,
      ),
  ];

  @override
  Future<List<ClosureCommitRow>> commits(String beaconId) async => [
    ClosureCommitRow(voterId: _otherVoterId, committedAt: _peerCommittedAt),
  ];

  @override
  Future<List<ClosureMarkRow>> marks(String beaconId) async => [
    ClosureMarkRow(markerId: _voterId, targetId: _otherVoterId, updatedAt: _t0),
    ClosureMarkRow(
      markerId: _otherVoterId,
      targetId: _voterId,
      updatedAt: _t0,
    ),
  ];

  @override
  Future<String?> story(String beaconId) async => 'A story';

  @override
  Future<ClosureResultRow?> resultFor({
    required String beaconId,
    required String userId,
  }) async => ClosureResultRow(
    beaconId: beaconId,
    epoch: 1,
    userId: userId,
    outcome: ClosureOutcome.done,
    band: ClosureBand.raised,
    draftFlag: ClosureResultDraftFlag.none,
    helped: 0.42,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Beacons implements BeaconRepositoryPort {
  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async {
    if (beaconId != _beaconId) throw IdNotFoundException(id: beaconId);
    return BeaconEntity(
      id: _beaconId,
      title: 't',
      author: const UserEntity(id: _authorId),
      createdAt: _t0,
      updatedAt: _t0,
      status: BeaconStatus.reviewOpen,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Commitments implements CommitmentRepositoryPort {
  @override
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(
    String beaconId,
  ) async {
    CommitmentEvent ev(int seq, String user, CommitmentEventKind kind) =>
        CommitmentEvent(
          id: 'CE$seq',
          seq: seq,
          beaconId: beaconId,
          userId: user,
          actorUserId: user == _blockedId ? _authorId : user,
          kind: kind,
          createdAt: _t0,
        );
    return {
      _blockedId: [
        ev(1, _blockedId, CommitmentEventKind.acknowledged),
        ev(2, _blockedId, CommitmentEventKind.blockedCleanup),
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoHelpOffers implements HelpOfferRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PassThroughUow implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoSettlement implements AttentionSystemSettlementPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoReceipts implements ClosureReceiptsPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NoFinalizer implements ClosureFinalizerPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Top-level keys whose value is neither null nor an empty list (booleans
/// count: a populated `canCloseNow: false` is still information).
Set<String> _nonNullKeys(Map<String, dynamic> m) => {
  for (final e in m.entries)
    if (e.value != null &&
        !(e.value is Iterable && (e.value as Iterable).isEmpty))
      e.key,
};

/// Every JSON number anywhere in [node].
List<num> _numbers(Object? node) => [
  if (node is num) node,
  if (node is Map)
    for (final v in node.values) ..._numbers(v),
  if (node is Iterable)
    for (final v in node) ..._numbers(v),
];
