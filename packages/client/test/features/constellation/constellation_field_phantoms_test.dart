// Read the new domain fields through the pre-feature Field type so the
// baseline can exercise the real load instead of failing compilation.
// ignore_for_file: avoid_dynamic_calls

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_anchors_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/data/repository/constellation_anchor_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

const _viewerId = 'Uviewer000001';
const _phantomId = 'PH0123456789ab';
const _phantom = ConstellationAnchorPhantomTarget(_phantomId);
const _person = ConstellationAnchorPersonTarget('Upeer00000001');
const _request = ConstellationAnchorBeaconTarget('Breq000000001');
const _position = ConstellationAnchorPosition(
  xUnits: 1.5,
  yUnits: -2.25,
  coordinateSpaceVersion: 1,
);
const _fetchedPosition = ConstellationAnchorPosition(
  xUnits: -4.5,
  yUnits: 3.75,
  coordinateSpaceVersion: 1,
);
const _fullFetch = 'ConstellationFieldFetch';
const _anchorsFetch = 'ConstellationAnchorsFetch';
const _apply = 'ConstellationAnchorsApply';
const Function _newStore = ConstellationFieldStoreCase.new;
final _createdAt = DateTime.utc(2026, 11, 1, 10);

void main() {
  test(
    'the release Field enables adding people without accounts by default',
    () async {
      const releaseDefault = kPhantomsEnabled;
      await withRemoteWire(
        {},
        <WireSent>[],
        (remote) async {
          final field = _FieldHarness(remote);
          expect(
            (releaseDefault, field.store.phantomsEnabled),
            (true, true),
            reason:
                'Both the release constant and the default store enable '
                'people without accounts',
          );
        },
      );
    },
  );

  test('a Field load preserves names, tags and invite details and clears an '
      'empty follow-up snapshot', () async {
    var rows = [
      _phantomJson(),
      _phantomJson(
        id: 'PH1234567890ab',
        name: 'Mira',
        emoji: null,
        inviteState: 'none',
        hasPrivateAvatar: true,
        tags: const [],
        pinState: 'pinned',
      ),
    ];
    final sent = <WireSent>[];
    await withRemoteWire(
      {},
      sent,
      (remote) async {
        final field = _FieldHarness(remote, enabled: true);
        await field.load();

        expect(_phantomsOf(field.snapshot).map(_phantomValues), [
          {
            'id': _phantomId,
            'displayName': 'Anna',
            'emoji': '🌿',
            'hasPrivateAvatar': false,
            'ownTagIds': ['tag1'],
            'pinState': null,
            'inviteState': 'live',
            'createdAt': _createdAt,
          },
          {
            'id': 'PH1234567890ab',
            'displayName': 'Mira',
            'emoji': null,
            'hasPrivateAvatar': true,
            'ownTagIds': <String>[],
            'pinState': 'pinned',
            'inviteState': 'none',
            'createdAt': _createdAt,
          },
        ]);

        rows = [];
        await field.load();
        expect(_phantomsOf(field.snapshot), isEmpty);
        _expectFullReads(sent, count: 2);
      },
      responseFor: (_) async => _fieldJson(phantoms: rows),
      selectResponse: _applyPhantomSelection,
    );
  });

  test('the disabled Field and its Cubit load successfully without exposing '
      'phantoms or their anchors, while opting in admits both', () async {
    final otherTargets = [_person, _request];
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        _fullFetch: _fieldJson(
          phantoms: [_phantomJson()],
          anchors: [
            for (final target in [...otherTargets, _phantom])
              _anchorJson(target, 5),
          ],
        ),
      },
      sent,
      (remote) async {
        final disabled = _FieldHarness(remote, enabled: false);
        final cubit = ConstellationCubit(
          case_: disabled.store,
          viewer: const Profile(id: _viewerId),
          loadOnCreate: false,
        );
        addTearDown(cubit.close);
        await cubit.load();

        expect(cubit.state.loadError, isNull, reason: 'A mixed snapshot loads');
        final expectedPins = [
          for (final target in otherTargets) _anchor(target, 5),
        ];
        expect(disabled.snapshot.loadedAt, _createdAt);
        expect(_phantomsOf(disabled.snapshot), isEmpty);
        expect(disabled.projection.anchors, unorderedEquals(expectedPins));

        final cubitField = cubit.state.field;
        expect(cubitField, isNotNull);
        expect(cubitField!.loadedAt, _createdAt);
        expect(_phantomsOf(cubitField), isEmpty);
        expect(
          cubitField.resolvedAnchorProjection.anchors,
          unorderedEquals(expectedPins),
          reason: 'The Cubit exposes only person and Request anchors',
        );

        disabled.store.setVisible(false);
        disabled.phantomHint();
        await disabled.advance(const Duration(seconds: 3));
        _expectFullReads(sent, count: 1);
        disabled.store.setVisible(true);
        await disabled.flush();
        _expectFullReads(sent, count: 1);

        disabled.phantomHint();
        await disabled.advance(const Duration(minutes: 6));
        _expectFullReads(sent, count: 1);

        final enabled = _FieldHarness(remote, enabled: true);
        await enabled.load();
        expect(
          _phantomsOf(enabled.snapshot).map(_phantomValues),
          [containsPair('id', _phantomId)],
        );
        expect(
          enabled.projection.anchors,
          unorderedEquals([
            for (final target in [...otherTargets, _phantom])
              _anchor(target, 5),
          ]),
        );
        _expectFullReads(sent, count: 2);
      },
    );
  });

  test('place a phantom through V2 and settle its returned position while '
      'retaining existing person and Request pins', () async {
    final targets = [_person, _request, _phantom];
    final sent = <WireSent>[];
    final paths = <String>[];
    await withRemoteWire(
      {
        _fullFetch: _fieldJson(),
        _apply: _applyJson(targets),
      },
      sent,
      (remote) async {
        final field = _FieldHarness(remote, enabled: true);
        await field.load();
        field.seedPins();
        final before = field.projection;
        _expectIgnoredPhantomSettlements(field, deleting: false);

        final covered = field.store.current.coveredRevision.value;
        final reply = await ConstellationAnchorRepository(remote).apply(
          ops: [
            for (final target in targets)
              ConstellationAnchorApplyOp(
                clientOpId: target.id,
                kind: ConstellationAnchorOpKind.upsert,
                target: target,
                position: _position,
              ),
          ],
          params: ConstellationFieldMembershipFilters.defaults,
        );

        expect(paths.last, '/api/v2/graphql');
        expect(sent.last.operationName, _apply);
        final ops = (sent.last.variables['ops'] as List<Object?>)
            .cast<Map<String, dynamic>>();
        expect(
          ops.map((op) => [op['targetKind'], op['targetId'], op['position']]),
          [
            ['PERSON', _person.id, _wirePosition(_position)],
            ['BEACON', _request.id, _wirePosition(_position)],
            ['PHANTOM', _phantomId, _wirePosition(_position)],
          ],
        );
        final expected = [for (final target in targets) _anchor(target, 7)];
        expect(reply.results.map((op) => op.anchor), expected);
        _expectFreshPhantomAcknowledgement(reply, covered);

        field.store.settle(reply, () {});
        expect(field.projection.anchors, unorderedEquals(expected));
        expect(field.projection.pinnedPeers, before.pinnedPeers);
        expect(field.projection.pinnedRequests, before.pinnedRequests);
        expect(field.store.current.coveredRevision, _revision(7));
      },
      requestPaths: paths,
    );
  });

  test('deleting an acknowledged phantom placement leaves person and Request '
      'pins intact', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        _fullFetch: _fieldJson(),
        _apply: _applyJson([_phantom], deleting: true),
      },
      sent,
      (remote) async {
        final field = _FieldHarness(remote, enabled: true);
        await field.load();
        field.seedPins(includePhantom: true);
        final before = field.projection;
        expect(before.anchors, contains(_anchor(_phantom, 6)));
        _expectIgnoredPhantomSettlements(field, deleting: true);

        final covered = field.store.current.coveredRevision.value;
        final reply = await ConstellationAnchorRepository(remote).apply(
          ops: const [
            ConstellationAnchorApplyOp(
              clientOpId: _phantomId,
              kind: ConstellationAnchorOpKind.delete,
              target: _phantom,
            ),
          ],
          params: ConstellationFieldMembershipFilters.defaults,
        );
        final ops = (sent.last.variables['ops'] as List<Object?>)
            .cast<Map<String, dynamic>>();
        expect(sent.last.operationName, _apply);
        expect(ops.single, containsPair('kind', 'DELETE'));
        expect(ops.single, containsPair('targetKind', 'PHANTOM'));
        expect(ops.single, containsPair('targetId', _phantomId));
        _expectFreshPhantomAcknowledgement(reply, covered);
        expect(reply.results.single.anchor, isNull);

        field.store.settle(reply, () {});
        expect(
          field.projection.anchors,
          unorderedEquals([_anchor(_person, 6), _anchor(_request, 6)]),
        );
        expect(field.projection.pinnedPeers, before.pinnedPeers);
        expect(field.projection.pinnedRequests, before.pinnedRequests);
        expect(field.store.current.coveredRevision, _revision(7));
      },
    );
  });

  test('the GraphQL anchor adapters round-trip PERSON, BEACON and PHANTOM', () {
    for (final (target, wireName) in [
      (_person, 'PERSON'),
      (_request, 'BEACON'),
      (_phantom, 'PHANTOM'),
    ]) {
      final original = _anchor(target, 7, position: _fetchedPosition);
      final wireKind = targetKindToWire(original.target.kind);
      expect(wireKind.name, wireName);

      final decoded = mapWireAnchor(
        targetKind: wireKind,
        targetId: original.target.id,
        xUnits: original.position.xUnits,
        yUnits: original.position.yUnits,
        coordinateSpaceVersion: original.position.coordinateSpaceVersion,
        revision: original.revision.toDecimalString(),
        placedAt: original.placedAt.toIso8601String(),
      );
      expect(decoded, original, reason: '$wireName round-trips unchanged');
    }
  });

  test('an anchor snapshot decodes phantom, person and Request targets', () {
    final targets = [_person, _request, _phantom];
    final request = GConstellationAnchorsFetchReq((builder) {
      builder.vars
        ..showClosed = false
        ..participatedOnly = false;
    });
    final response = request.parseData(
      _fieldJson(
        anchors: [for (final target in targets) _anchorJson(target, 5)],
      ),
    )!;

    final field = mapConstellationFieldFromAnchorsFetch(
      response.constellationField,
    );

    expect(field.resolvedAnchorProjection.anchors, [
      for (final target in targets) _anchor(target, 5),
    ]);
  });

  test('a newer anchor hint refreshes the settled phantom position and '
      'advances the covered revision', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        _fullFetch: _fieldJson(),
        _anchorsFetch: _fieldJson(
          revision: 8,
          anchors: [_anchorJson(_phantom, 8, position: _fetchedPosition)],
        ),
      },
      sent,
      (remote) async {
        final field = _FieldHarness(remote, enabled: true);
        await field.load();
        field.seedPins(includePhantom: true);
        expect(field.projection.anchors, contains(_anchor(_phantom, 6)));

        final refreshed = field.store.changes
            .firstWhere((state) => state.coveredRevision == _revision(8))
            .timeout(
              const Duration(seconds: 1),
              onTimeout: () => field.store.current,
            );
        field.hint(
          RealtimeEntityKind.constellationAnchor,
          _viewerId,
          revision: BigInt.from(8),
        );
        final state = await refreshed;

        expect(sent.map((call) => call.operationName), [
          _fullFetch,
          _anchorsFetch,
        ]);
        expect(
          state.coveredRevision.value,
          BigInt.from(8),
          reason: 'The ANCHORS response must apply the fetched revision',
        );
        expect(field.projection.anchors, [
          _anchor(_phantom, 8, position: _fetchedPosition),
        ]);
      },
    );
  });

  test(
    'a phantom change on a visible Field starts a FULL refresh within '
    'the urgent window',
    () async {
      final sent = <WireSent>[];
      await withRemoteWire({_fullFetch: _fieldJson()}, sent, (remote) async {
        final field = _FieldHarness(remote, enabled: true);
        await field.load();

        field.phantomHint();
        await field.advance(const Duration(milliseconds: 219));
        _expectFullReads(sent, count: 1);

        // The fake clock stops at the deadline, with no wait for lazy refresh.
        await field.advance(const Duration(milliseconds: 2001));
        _expectFullReads(sent, count: 2);
      });
    },
    timeout: const Timeout(Duration(seconds: 4)),
  );

  test(
    'a phantom change while the Field is hidden refreshes once on return',
    () async {
      final sent = <WireSent>[];
      await withRemoteWire({_fullFetch: _fieldJson()}, sent, (remote) async {
        final field = _FieldHarness(remote, enabled: true);
        await field.load();

        field.store.setVisible(false);
        field.phantomHint();
        await field.advance(const Duration(seconds: 3));
        _expectFullReads(sent, count: 1);

        field.store.setVisible(true);
        await field.flush();
        _expectFullReads(sent, count: 2);
        await field.advance(const Duration(seconds: 3));
        _expectFullReads(sent, count: 2);
      });
    },
  );
}

void _expectIgnoredPhantomSettlements(
  _FieldHarness field, {
  required bool deleting,
}) {
  final covered = field.store.current.coveredRevision;
  expect(covered, _revision(6));
  final before = field.projection;

  for (final (beforeRevision, targetRevision, replayed, reason) in [
    (7, 8, true, 'a replayed acknowledgement newer than coverage'),
    (5, 6, false, 'a late acknowledgement at the covered revision'),
  ]) {
    field.store.settle(
      ConstellationAnchorApplyResult(
        beforeRevision: _revision(beforeRevision),
        afterRevision: _revision(targetRevision),
        results: [
          ConstellationAnchorOpResult(
            clientOpId: _phantomId,
            status: ConstellationAnchorOpStatus.ok,
            target: _phantom,
            resultingTargetRevision: _revision(targetRevision),
            anchor: deleting
                ? null
                : _anchor(_phantom, targetRevision, position: _fetchedPosition),
            replayed: replayed,
          ),
        ],
      ),
      () {},
    );
    expect(field.projection, before, reason: 'Ignore $reason');
    expect(field.store.current.coveredRevision, covered);
  }
}

void _expectFreshPhantomAcknowledgement(
  ConstellationAnchorApplyResult reply,
  BigInt covered,
) {
  final op = reply.results.singleWhere((op) => op.target == _phantom);
  expect(op.status, ConstellationAnchorOpStatus.ok);
  expect(op.replayed, isFalse);
  expect(op.resultingTargetRevision?.value, greaterThan(covered));
}

void _expectFullReads(List<WireSent> sent, {required int count}) {
  expect(sent, hasLength(count), reason: 'Observed Field requests: $sent');
  for (final call in sent) {
    expect(call.operationName, _fullFetch);
    expect(call.variables, containsPair('projection', 'FULL'));
  }
}

Map<String, dynamic> _phantomJson({
  String id = _phantomId,
  String name = 'Anna',
  String? emoji = '🌿',
  String inviteState = 'live',
  bool hasPrivateAvatar = false,
  List<String> tags = const ['tag1'],
  String? pinState,
}) => {
  '__typename': 'v2_ConstellationPhantom',
  'id': id,
  'displayName': name,
  'emoji': emoji,
  'hasPrivateAvatar': hasPrivateAvatar,
  'ownTagIds': tags,
  'pinState': pinState,
  'inviteState': inviteState,
  'createdAt': '2026-11-01T10:00:00Z',
};

Map<String, dynamic> _fieldJson({
  int revision = 5,
  List<Map<String, dynamic>> phantoms = const [],
  List<Map<String, dynamic>> anchors = const [],
}) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-01T10:00:00Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': <String>[],
    'peers': <Object?>[],
    'edges': <Object?>[],
    'requests': <Object?>[],
    'posts': <Object?>[],
    'memberWebs': <Object?>[],
    'phantoms': phantoms,
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '$revision',
      'anchors': anchors,
      'pinnedPeers': <Object?>[],
      'pinnedRequests': <Object?>[],
      'supportPeers': <Object?>[],
      'supportEdges': <Object?>[],
      'serverFilteredBeaconIds': <String>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

/// A GraphQL server only sends phantom fields the client requests.
Map<String, dynamic> _applyPhantomSelection(
  String query,
  Map<String, dynamic> data,
) {
  final operation = parseString(
    query,
  ).definitions.whereType<OperationDefinitionNode>().single;
  final field = operation.selectionSet.selections
      .whereType<FieldNode>()
      .singleWhere((node) => node.name.value == 'constellationField');
  final selections = field.selectionSet!.selections.whereType<FieldNode>();
  final phantomFields = [
    for (final node in selections)
      if (node.name.value == 'phantoms')
        ...node.selectionSet!.selections.whereType<FieldNode>().map(
          (field) => field.name.value,
        ),
  ];
  final snapshot = data['constellationField'] as Map<String, dynamic>;
  final rows = (snapshot['phantoms'] as List<Object?>)
      .cast<Map<String, dynamic>>();
  return {
    ...data,
    'constellationField': {
      for (final entry in snapshot.entries)
        if (entry.key != 'phantoms') entry.key: entry.value,
      if (phantomFields.isNotEmpty)
        'phantoms': [
          for (final row in rows)
            {
              '__typename': row['__typename'],
              for (final key in phantomFields) key: row[key],
            },
        ],
    },
  };
}

Map<String, Object> _wirePosition(ConstellationAnchorPosition position) => {
  'xUnits': position.xUnits,
  'yUnits': position.yUnits,
  'coordinateSpaceVersion': position.coordinateSpaceVersion,
};

Map<String, dynamic> _anchorJson(
  ConstellationAnchorTarget target,
  int revision, {
  ConstellationAnchorPosition position = _position,
}) => {
  '__typename': 'v2_ConstellationAnchor',
  'targetKind': target.kind.wireValue,
  'targetId': target.id,
  ..._wirePosition(position),
  'revision': '$revision',
  'placedAt': '2026-11-01T10:00:00Z',
};

Map<String, dynamic> _applyJson(
  List<ConstellationAnchorTarget> targets, {
  bool deleting = false,
}) => {
  'constellationAnchorsApply': {
    '__typename': 'v2_ConstellationAnchorsApplyResult',
    'beforeRevision': '6',
    'afterRevision': '7',
    'results': [
      for (final target in targets)
        {
          '__typename': 'v2_ConstellationAnchorOpResult',
          'clientOpId': target.id,
          'status': 'OK',
          'resultingTargetRevision': '7',
          'anchor': deleting ? null : _anchorJson(target, 7),
          'replayed': false,
        },
    ],
  },
};

ConstellationAnchorRevision _revision(int revision) =>
    ConstellationAnchorRevision(BigInt.from(revision));

ConstellationAnchor _anchor(
  ConstellationAnchorTarget target,
  int revision, {
  ConstellationAnchorPosition position = _position,
}) => ConstellationAnchor(
  target: target,
  position: position,
  revision: _revision(revision),
  placedAt: _createdAt,
);

/// The current Field has no phantom collection. Treat that as zero delivered
/// records so the test can report the missing data after a successful load.
Iterable<Object> _phantomsOf(ConstellationField field) {
  try {
    return (field as dynamic).phantoms as Iterable<Object>;
    // Absence of the pre-rollout getter is the one expected baseline error.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    return const [];
  }
}

Map<String, Object?> _phantomValues(dynamic phantom) => {
  'id': phantom.id as String,
  'displayName': phantom.displayName as String,
  'emoji': phantom.emoji as String?,
  'hasPrivateAvatar': phantom.hasPrivateAvatar as bool,
  'ownTagIds': phantom.ownTagIds as Iterable<String>,
  'pinState': _wireValue(phantom.pinState as Object?),
  'inviteState': _wireValue(phantom.inviteState as Object),
  'createdAt': phantom.createdAt as DateTime,
};

Object? _wireValue(Object? value) => value is Enum ? value.name : value;

typedef _GatedStoreFactory =
    ConstellationFieldStoreCase Function(
      ConstellationRepositoryPort,
      ConstellationAccountPort,
      ClockPort,
      WakeUpPort,
      RealtimeSyncCase, {
      required Env env,
      required Logger logger,
      required bool phantomsEnabled,
    });

final class _FieldHarness {
  _FieldHarness(RemoteApiService remote, {bool? enabled}) {
    final logger = Logger.detached('FieldWireTest');
    final repository = ConstellationRepository(remote);
    const account = _Account();
    const env = Env.fromEnvironment();
    const factory = _newStore;
    // Fall through to the pre-rollout constructor so that tests exercise the
    // existing repository/store path and fail at the observable result.
    store = enabled != null && factory is _GatedStoreFactory
        ? factory(
            repository,
            account,
            clock,
            wakeUp,
            sync.case_,
            env: env,
            logger: logger,
            phantomsEnabled: enabled,
          )
        : ConstellationFieldStoreCase(
            repository,
            account,
            clock,
            wakeUp,
            sync.case_,
            env: env,
            logger: logger,
          );
    final lease = store.lease();
    addTearDown(() async {
      lease.dispose();
      await store.dispose();
      await sync.port.dispose();
    });
  }

  final clock = FakeClockPort(_createdAt);
  final wakeUp = FakeWakeUpPort();
  final sync = buildTestRealtimeSync();
  late final ConstellationFieldStoreCase store;

  ConstellationField get snapshot => store.current.field!;
  ConstellationAnchorProjection get projection =>
      snapshot.resolvedAnchorProjection;

  Future<void> load() => store.requestRefresh(ConstellationRefreshReason.load);

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Future<void> advance(Duration duration) async {
    await flush();
    clock.advance(duration);
    wakeUp.elapse(duration);
    await flush();
  }

  void hint(RealtimeEntityKind kind, String id, {BigInt? revision}) {
    sync.port.emitChange(
      RealtimeEntityChange(
        kind: kind,
        aggregateId: id,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
        revision: revision,
      ),
    );
  }

  void phantomHint() => hint(RealtimeEntityKind.phantom, _phantomId);

  void seedPins({bool includePhantom = false}) {
    store.settle(
      ConstellationAnchorApplyResult(
        beforeRevision: _revision(5),
        afterRevision: _revision(6),
        results: [
          for (final target in [
            _person,
            _request,
            if (includePhantom) _phantom,
          ])
            ConstellationAnchorOpResult(
              clientOpId: 'seed-${target.id}',
              status: ConstellationAnchorOpStatus.ok,
              anchor: _anchor(target, 6),
              resultingTargetRevision: _revision(6),
            ),
        ],
      ),
      () {},
      capturedPeers: [ConstellationPerson(id: _person.id, displayName: 'Leo')],
      capturedRequests: [
        ConstellationRequest(
          id: _request.id,
          authorId: _person.id,
          title: 'Move a bookshelf',
          status: 0,
        ),
      ],
    );
    expect(projection.pinnedPeers.map((peer) => peer.id), [_person.id]);
    expect(projection.pinnedRequests.map((request) => request.id), [
      _request.id,
    ]);
  }
}

final class _Account implements ConstellationAccountPort {
  const _Account();

  @override
  Stream<String> get currentAccountChanges => Stream.value(_viewerId);
}
