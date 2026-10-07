// A19: the real `ClosureRepository` over the real `RemoteApiService` and Ferry
// link chain; only the HTTP transport is faked (via `http.runWithClient`).
// Pins the mapping of Arch §7 responses to domain entities, the variables each
// operation sends, and the typed exceptions for the 1800-space error codes.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_client/realtime_socket.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura/features/closure/domain/entity/closure_band.dart';
import 'package:tentura/features/closure/domain/entity/closure_draft_flag.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';

const _beaconId = 'Bclosure00001';

typedef _Sent = ({String operationName, Map<String, dynamic> variables});

/// Runs [body] against a real [RemoteApiService] whose transport answers each
/// GraphQL operation (keyed by operation name) with [responses].
Future<void> _withRemote(
  Map<String, Map<String, dynamic>> responses,
  List<_Sent> sent,
  Future<void> Function(ClosureRepository repo) body, {
  Map<String, Map<String, dynamic>> errors = const {},
}) => http.runWithClient(
  () async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    try {
      await remote.setSessionAuth();
      await body(ClosureRepository(remote));
    } finally {
      await remote.close();
    }
  },
  () => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': 'Uauthor000001',
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final json = jsonDecode(request.body) as Map<String, dynamic>;
    final name = json['operationName'] as String;
    sent.add((
      operationName: name,
      variables: (json['variables'] as Map).cast<String, dynamic>(),
    ));
    final error = errors[name];
    if (error != null) {
      return http.Response(
        jsonEncode({
          'data': null,
          'errors': [error],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({'data': responses[name]}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

Map<String, dynamic> _stateJson() => {
  '__typename': 'ClosureState',
  'epoch': 2,
  'status': 3,
  'role': 'author',
  'members': [
    {
      '__typename': 'ClosureMember',
      'id': 'Uhelper000001',
      'displayName': 'Helper One',
      'avatarId': 'Aavatar00001',
      'helpTypes': ['tools'],
      'offerText': 'I can lend a ladder',
      'notInRequest': false,
      'departure': null,
    },
    {
      '__typename': 'ClosureMember',
      'id': 'Uhelper000002',
      'displayName': null,
      'avatarId': null,
      'helpTypes': null,
      'offerText': null,
      'notInRequest': true,
      'departure': 'removed',
    },
  ],
  'outcomes': [
    {
      '__typename': 'ClosureOutcomeEntry',
      'helperId': 'Uhelper000001',
      'outcome': 'done',
    },
    {
      '__typename': 'ClosureOutcomeEntry',
      'helperId': 'Uhelper000002',
      'outcome': 'cantJudge',
    },
  ],
  'split': [
    {
      '__typename': 'ClosureSplitEntry',
      'helperId': 'Uhelper000001',
      'pct': 60,
    },
  ],
  'mySupport': ['Uhelper000001'],
  'inCalcText': 'counted',
  'myMarks': ['Uhelper000002'],
  'closesAt': '2026-10-05T12:00:00.000Z',
  'earlyCloseAt': '2026-10-03T09:30:00.000Z',
  'canCloseNow': true,
  'canReopen': false,
  'story': 'It went well',
};

Map<String, dynamic> _codeError(int code) => {
  'message': 'closure',
  'extensions': {'code': code.toString()},
};

void main() {
  test('fetchState maps ClosureState into the domain entity', () async {
    final sent = <_Sent>[];
    await _withRemote(
      {
        'ClosureState': {
          '__typename': 'query_root',
          'closureState': _stateJson(),
        },
      },
      sent,
      (repo) async {
        final ClosureState s = await repo.fetchState(_beaconId);

        expect(s.epoch, 2);
        expect(s.status, 3);
        expect(s.members, hasLength(2));
        expect(s.role, ClosureRole.author);
        final m1 = s.members.first;
        expect(m1.id, 'Uhelper000001');
        expect(m1.displayName, 'Helper One');
        expect(m1.avatarId, 'Aavatar00001');
        expect(m1.helpTypes, ['tools']);
        expect(m1.offerText, 'I can lend a ladder');
        expect(m1.notInRequest, isFalse);
        expect(m1.departure, isNull);
        final m2 = s.members.last;
        expect(m2.id, 'Uhelper000002');
        expect(m2.displayName, isNull);
        expect(m2.avatarId, isNull);
        expect(m2.helpTypes, anyOf(isNull, isEmpty));
        expect(m2.offerText, isNull);
        expect(m2.notInRequest, isTrue);
        expect(m2.departure, 'removed');
        expect(s.outcomes, {
          'Uhelper000001': ClosureOutcome.done,
          'Uhelper000002': ClosureOutcome.cantJudge,
        });
        expect(s.split, {'Uhelper000001': 60});
        expect(s.mySupport, ['Uhelper000001']);
        expect(s.inCalcText, 'counted');
        expect(s.myMarks, ['Uhelper000002']);
        expect(s.closesAt, DateTime.utc(2026, 10, 5, 12));
        expect(s.closesAt.isUtc, isTrue);
        expect(s.earlyCloseAt, DateTime.utc(2026, 10, 3, 9, 30));
        expect(s.canCloseNow, isTrue);
        expect(s.canReopen, isFalse);
        expect(s.story, 'It went well');
      },
    );
    expect(sent.single.operationName, 'ClosureState');
    expect(sent.single.variables['beaconId'], _beaconId);
  });

  test('fetchState maps extensionsUsed from the wire', () async {
    for (final used in [0, 1, 2]) {
      final json = _stateJson()..['extensionsUsed'] = used;
      await _withRemote(
        {
          'ClosureState': {'__typename': 'query_root', 'closureState': json},
        },
        <_Sent>[],
        (repo) async {
          final s = await repo.fetchState(_beaconId);
          expect(s.extensionsUsed, used);
        },
      );
    }
  });

  test('fetchState defaults an omitted extensionsUsed key to 0', () async {
    final json = _stateJson()
      ..['role'] = 'voter'
      ..remove('extensionsUsed');
    await _withRemote(
      {
        'ClosureState': {'__typename': 'query_root', 'closureState': json},
      },
      <_Sent>[],
      (repo) async {
        final s = await repo.fetchState(_beaconId);
        expect(s.extensionsUsed, 0);
      },
    );
  });

  test('fetchState maps a voter view with every nullable absent', () async {
    final json = _stateJson()
      ..['role'] = 'voter'
      ..['outcomes'] = null
      ..['split'] = null
      ..['mySupport'] = null
      ..['inCalcText'] = null
      ..['myMarks'] = null
      ..['earlyCloseAt'] = null
      ..['canCloseNow'] = null
      ..['canReopen'] = null
      ..['story'] = null;
    await _withRemote(
      {
        'ClosureState': {'__typename': 'query_root', 'closureState': json},
      },
      <_Sent>[],
      (repo) async {
        final s = await repo.fetchState(_beaconId);
        expect(s.role, ClosureRole.voter);
        expect(s.outcomes, isNull);
        expect(s.split, isNull);
        expect(s.mySupport, anyOf(isNull, isEmpty));
        expect(s.inCalcText, isNull);
        expect(s.myMarks, anyOf(isNull, isEmpty));
        expect(s.earlyCloseAt, isNull);
        expect(s.canCloseNow, isFalse);
        expect(s.canReopen, isFalse);
        expect(s.story, isNull);
        expect(s.members, hasLength(2));
      },
    );
  });

  test('fetchState maps the member role and each outcome value', () async {
    final json = _stateJson()
      ..['role'] = 'member'
      ..['outcomes'] = [
        {'helperId': 'Ua', 'outcome': 'done', '__typename': 'ClosureOutcomeEntry'},
        {'helperId': 'Ub', 'outcome': 'notDone', '__typename': 'ClosureOutcomeEntry'},
        {'helperId': 'Uc', 'outcome': 'cantJudge', '__typename': 'ClosureOutcomeEntry'},
      ];
    await _withRemote(
      {
        'ClosureState': {'__typename': 'query_root', 'closureState': json},
      },
      <_Sent>[],
      (repo) async {
        final s = await repo.fetchState(_beaconId);
        expect(s.role, ClosureRole.member);
        expect(s.outcomes, {
          'Ua': ClosureOutcome.done,
          'Ub': ClosureOutcome.notDone,
          'Uc': ClosureOutcome.cantJudge,
        });
      },
    );
  });

  test('fetchResultForViewer maps every band and draft flag', () async {
    final bands = {
      'raised': ClosureBand.raised,
      'asIfSilent': ClosureBand.asIfSilent,
      'lowered': ClosureBand.lowered,
      'none': ClosureBand.none,
    };
    final flags = {
      'none': ClosureDraftFlag.none,
      'notCounted': ClosureDraftFlag.notCounted,
      'lastEditNotCounted': ClosureDraftFlag.lastEditNotCounted,
    };
    for (final b in bands.entries) {
      for (final f in flags.entries) {
        await _withRemote(
          {
            'ClosureResultForViewer': {
              '__typename': 'query_root',
              'closureResultForViewer': {
                '__typename': 'ClosureResult',
                'outcome': 'done',
                'band': b.key,
                'draftFlag': f.key,
                'marks': <String>[],
                'story': 'told',
              },
            },
          },
          <_Sent>[],
          (repo) async {
            final r = (await repo.fetchResultForViewer(_beaconId))!;
            expect(r.outcome, ClosureOutcome.done);
            expect(r.band, b.value);
            expect(r.draftFlag, f.value);
            expect(r.marks, isEmpty);
            expect(r.story, 'told');
          },
        );
      }
    }
  });

  test('fetchResultForViewer maps band, draft flag and null', () async {
    await _withRemote(
      {
        'ClosureResultForViewer': {
          '__typename': 'query_root',
          'closureResultForViewer': {
            '__typename': 'ClosureResult',
            'outcome': 'notDone',
            'band': 'lowered',
            'draftFlag': 'lastEditNotCounted',
            'marks': ['Uhelper000001'],
            'story': null,
          },
        },
      },
      <_Sent>[],
      (repo) async {
        final r = await repo.fetchResultForViewer(_beaconId);
        expect(r, isNotNull);
        expect(r!.outcome, ClosureOutcome.notDone);
        expect(r.band, ClosureBand.lowered);
        expect(r.draftFlag, ClosureDraftFlag.lastEditNotCounted);
        expect(r.marks, ['Uhelper000001']);
        expect(r.story, isNull);
      },
    );

    await _withRemote(
      {
        'ClosureResultForViewer': {
          '__typename': 'query_root',
          'closureResultForViewer': null,
        },
      },
      <_Sent>[],
      (repo) async => expect(await repo.fetchResultForViewer(_beaconId), isNull),
    );
  });

  test('toggleSupport sends the epoch guard and returns released id', () async {
    final sent = <_Sent>[];
    await _withRemote(
      {
        'ClosureToggleSupport': {
          '__typename': 'mutation_root',
          'closureToggleSupport': {
            '__typename': 'ClosureToggleResult',
            'released': 'Uhelper000009',
          },
        },
      },
      sent,
      (repo) async {
        final released = await repo.toggleSupport(
          beaconId: _beaconId,
          expectedEpoch: 2,
          targetId: 'Uhelper000001',
          on: true,
        );
        expect(released, 'Uhelper000009');
      },
    );
    expect(sent.single.operationName, 'ClosureToggleSupport');
    expect(sent.single.variables, {
      'beaconId': _beaconId,
      'expectedEpoch': 2,
      'targetId': 'Uhelper000001',
      'on': true,
    });
  });

  test('saveAuthorSplit sends helperId/pct entries; null clears', () async {
    final sent = <_Sent>[];
    await _withRemote(
      {
        'ClosureSaveAuthorSplit': {
          '__typename': 'mutation_root',
          'closureSaveAuthorSplit': true,
        },
      },
      sent,
      (repo) async {
        await repo.saveAuthorSplit(
          beaconId: _beaconId,
          expectedEpoch: 2,
          split: {'Uhelper000001': 60, 'Uhelper000002': 40},
        );
        await repo.saveAuthorSplit(
          beaconId: _beaconId,
          expectedEpoch: 2,
          split: null,
        );
      },
    );
    expect(sent.first.variables['split'], [
      {'helperId': 'Uhelper000001', 'pct': 60},
      {'helperId': 'Uhelper000002', 'pct': 40},
    ]);
    expect(sent.last.variables['split'], isNull);
  });

  test('simple mutations send beaconId + expectedEpoch', () async {
    final sent = <_Sent>[];
    await _withRemote(
      {
        'ClosureSaveOutcome': {'closureSaveOutcome': true},
        'ClosureDone': {'closureDone': true},
        'ClosureSkip': {'closureSkip': true},
        'ClosureSetMark': {'closureSetMark': true},
        'ClosureSaveStory': {'closureSaveStory': true},
        'BeaconClose': {'beaconClose': true},
        'BeaconCloseNow': {'beaconCloseNow': true},
        'BeaconExtendClosure': {'beaconExtendClosure': true},
        'BeaconReopen': {'beaconReopen': true},
      },
      sent,
      (repo) async {
        await repo.saveOutcome(
          beaconId: _beaconId,
          expectedEpoch: 2,
          helperId: 'Uhelper000001',
          outcome: ClosureOutcome.cantJudge,
        );
        await repo.done(beaconId: _beaconId, expectedEpoch: 2);
        await repo.skip(beaconId: _beaconId, expectedEpoch: 2);
        await repo.setMark(
          beaconId: _beaconId,
          expectedEpoch: 2,
          targetId: 'Uhelper000001',
          on: false,
        );
        await repo.saveStory(
          beaconId: _beaconId,
          expectedEpoch: 2,
          body: 'story',
        );
        await repo.close(_beaconId);
        await repo.closeNow(beaconId: _beaconId, expectedEpoch: 2);
        await repo.extendClosure(beaconId: _beaconId, expectedEpoch: 2);
        await repo.reopen(beaconId: _beaconId, expectedEpoch: 2);
      },
    );
    expect(sent.map((s) => s.operationName), [
      'ClosureSaveOutcome',
      'ClosureDone',
      'ClosureSkip',
      'ClosureSetMark',
      'ClosureSaveStory',
      'BeaconClose',
      'BeaconCloseNow',
      'BeaconExtendClosure',
      'BeaconReopen',
    ]);
    expect(sent.first.variables['outcome'], 'cantJudge');
    expect(sent.first.variables['helperId'], 'Uhelper000001');
    expect(sent[3].variables['on'], false);
    expect(sent[4].variables['body'], 'story');
    for (final s in sent) {
      expect(s.variables['beaconId'], _beaconId);
    }
    for (final s in sent.where((s) => s.operationName != 'BeaconClose')) {
      expect(s.variables['expectedEpoch'], 2);
    }
  });

  group('error codes map to typed exceptions (code space 1800)', () {
    final cases = <int, Matcher>{
      1800: isA<ClosureNotAuthorException>(),
      1801: isA<ClosureNotVoterException>(),
      1802: isA<ClosureNotMemberException>(),
      1803: isA<ClosureStaleEpochException>(),
      1804: isA<ClosureWrongStatusException>(),
      1805: isA<ClosureReopenLimitException>(),
      1806: isA<ClosureExtendLimitException>(),
      1807: isA<ClosureNotReadyException>(),
      1808: isA<ClosureInvalidSplitException>(),
      1809: isA<ClosureSplitTooLargeException>(),
    };
    for (final e in cases.entries) {
      test('${e.key}', () async {
        await _withRemote(
          const {},
          <_Sent>[],
          (repo) async => expectLater(
            repo.done(beaconId: _beaconId, expectedEpoch: 1),
            throwsA(e.value),
          ),
          errors: {'ClosureDone': _codeError(e.key)},
        );
      });
    }

    test('queries map errors too (fetchState 1802)', () async {
      await _withRemote(
        const {},
        <_Sent>[],
        (repo) async => expectLater(
          repo.fetchState(_beaconId),
          throwsA(isA<ClosureNotMemberException>()),
        ),
        errors: {'ClosureState': _codeError(1802)},
      );
    });

    test(
      'beaconClose still reports a closed Request when the closure state '
      'read finds no epoch',
      () async {
        await _withRemote(
          {
            'BeaconClose': {'beaconClose': true},
            'ClosureState': {
              'closureState': {
                '__typename': 'ClosureState',
                'epoch': 0,
                'status': 1,
                'role': 'author',
                'members': <Object>[],
                'outcomes': <Object>[],
                'myMarks': <String>[],
                'closesAt': '2026-10-05T19:40:00.000Z',
                'canCloseNow': false,
                'canReopen': false,
                'extensionsUsed': 0,
              },
            },
          },
          <_Sent>[],
          (repo) async {
            final result = await repo.beaconClose(beaconId: _beaconId);
            expect(result.beaconId, _beaconId);
            // Finalized: the Request is closed and no review window is open.
            expect(result.state, 1);
            expect(result.closesAt, isNull);
          },
        );
      },
    );

    for (final code in [1002, 1802]) {
      test(
        'beaconClose propagates closure state error $code after close',
        () async {
          await _withRemote(
            {
              'BeaconClose': {'beaconClose': true},
            },
            <_Sent>[],
            (repo) async {
              await expectLater(
                repo.beaconClose(beaconId: _beaconId),
                throwsA(
                  code == 1002
                      ? isA<RemoteApiException>()
                      : isA<ClosureNotMemberException>(),
                ),
              );
            },
            errors: {'ClosureState': _codeError(code)},
          );
        },
      );
    }

    test('typed exceptions are localizable and numbered', () {
      expect(ClosureStaleEpochException.codeNumber, 1803);
      expect(const ClosureStaleEpochException().toEn, isNotEmpty);
      expect(const ClosureStaleEpochException().toRu, isNotEmpty);
    });
  });
}
