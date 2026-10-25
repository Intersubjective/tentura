import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_anchor_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../../support/constellation_store_fixture.dart';
import '../../../support/fake_clock_port.dart';
import '../../../support/fake_wake_up_port.dart';
import '../../../support/test_realtime_sync.dart';
import 'constellation_arrange_harness.dart';

/// Test server state shared by independently opened Field sessions. Only the
/// GraphQL boundary is faked; snapshots and favourite actions must be requested
/// by the real client code.
class LayoutHistoryServer {
  LayoutHistoryServer()
    : anchors = {
        arrangePersonOne: arrangePosition(1, 2),
        arrangePersonTwo: arrangePosition(-3, 4),
      };

  final Map<ConstellationAnchorTarget, ConstellationAnchorPosition> anchors;
  final snapshots = <LayoutHistorySnapshot>[];
  final events = <String>[];
  final operationIds = <String>[];
  final batches = <List<Map<String, dynamic>>>[];
  int revision = 10;
  int _sequence = 0;
  void Function()? onSave;
  void Function(String snapshotId)? onRestore;
  Completer<void>? applyGate;

  LayoutHistorySnapshot? get favourite =>
      snapshots.where((s) => s.kind == 0).firstOrNull;

  LayoutHistorySnapshot seed({
    required int kind,
    required DateTime createdAt,
    required Map<ConstellationAnchorTarget, ConstellationAnchorPosition> at,
    int reason = 0,
  }) {
    final snapshot = LayoutHistorySnapshot(
      id: 'LS-test-${++_sequence}',
      kind: kind,
      reason: reason,
      createdAt: createdAt,
      anchors: Map.of(at),
    );
    if (kind == 0) {
      final previous = favourite;
      if (previous != null) {
        snapshots.remove(previous);
        snapshots.add(
          LayoutHistorySnapshot(
            id: previous.id,
            kind: 1,
            reason: previous.reason,
            createdAt: previous.createdAt,
            anchors: previous.anchors,
          ),
        );
      }
    }
    snapshots.add(snapshot);
    return snapshot;
  }

  LayoutHistorySnapshot _save(int kind, int reason) {
    onSave?.call();
    events.add('save:$kind:$reason');
    return seed(
      kind: kind,
      reason: reason,
      createdAt: DateTime.utc(2026, 10, 25, 12).add(
        Duration(seconds: _sequence),
      ),
      at: anchors,
    );
  }

  Map<String, Object?> _anchor(
    ConstellationAnchorTarget target,
    ConstellationAnchorPosition position,
  ) => {
    '__typename': 'v2_ConstellationAnchor',
    'targetKind': target.kind == ConstellationAnchorTargetKind.person
        ? 'PERSON'
        : 'BEACON',
    'targetId': target.id,
    'xUnits': position.xUnits,
    'yUnits': position.yUnits,
    'coordinateSpaceVersion': position.coordinateSpaceVersion,
    'revision': '$revision',
    'placedAt': '2026-10-25T12:00:00.000Z',
  };

  late final client = MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return _response({
        'subject': 'ego',
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final vars = (body['variables'] as Map<String, dynamic>?) ?? {};
    final opId = vars['clientOpId'];
    if (opId is String) operationIds.add(opId);
    final before = revision;
    switch (body['operationName']) {
      case 'ConstellationLayoutSnapshots':
        final ordered = [...snapshots]
          ..sort((a, b) {
            final kind = a.kind.compareTo(b.kind);
            return kind != 0 ? kind : b.createdAt.compareTo(a.createdAt);
          });
        return _data('constellationLayoutSnapshots', [
          for (final s in ordered) s.wire,
        ]);
      case 'ConstellationLayoutSnapshotSave':
        final saved = _save(vars['kind'] as int, vars['reason'] as int);
        return _data('constellationLayoutSnapshotSave', saved.wire);
      case 'ConstellationLayoutFavouriteRestore':
        final id = vars['snapshotId'] as String;
        _save(1, 1);
        if (id.isEmpty) {
          snapshots.removeWhere((s) => s.kind == 0);
        } else {
          final source = snapshots.singleWhere((s) => s.id == id);
          seed(
            kind: 0,
            createdAt: DateTime.utc(2026, 10, 25, 12),
            at: source.anchors,
            reason: 1,
          );
        }
        return _data('constellationLayoutFavouriteRestore', true);
      case 'ConstellationLayoutSnapshotRestore':
        final source = snapshots.singleWhere(
          (s) => s.id == vars['snapshotId'],
        );
        _save(1, 1); // The restore endpoint saves history atomically.
        onRestore?.call(source.id);
        events.add('restore:${source.id}');
        anchors
          ..clear()
          ..addAll(source.anchors);
        revision++;
        return _data('constellationLayoutSnapshotRestore', source.wire);
      case 'ConstellationAnchorsReset':
        if (vars['saveHistory'] == true) _save(1, 2);
        final cleared = anchors.length;
        events.add('reset');
        anchors.clear();
        revision++;
        return _data('constellationAnchorsReset', {
          '__typename': 'v2_ConstellationAnchorsResetResult',
          'beforeRevision': '$before',
          'afterRevision': '$revision',
          'clearedCount': cleared,
          'replayed': false,
        });
      case 'ConstellationAnchorsApply':
        events.add('apply');
        final ops = (vars['ops'] as List).cast<Map<String, dynamic>>();
        batches.add(ops);
        await applyGate?.future;
        final results = <Map<String, Object?>>[];
        for (final op in ops) {
          final target = op['targetKind'] == 'PERSON'
              ? ConstellationAnchorTarget.person(op['targetId'] as String)
              : ConstellationAnchorTarget.beacon(op['targetId'] as String);
          revision++;
          final raw = op['position'] as Map<String, dynamic>?;
          if (op['kind'] == 'DELETE') {
            anchors.remove(target);
          } else {
            anchors[target] = ConstellationAnchorPosition(
              xUnits: (raw!['xUnits'] as num).toDouble(),
              yUnits: (raw['yUnits'] as num).toDouble(),
              coordinateSpaceVersion: raw['coordinateSpaceVersion'] as int,
            );
          }
          results.add({
            '__typename': 'v2_ConstellationAnchorOpResult',
            'clientOpId': op['clientOpId'],
            'status': 'OK',
            'reason': null,
            'resultingTargetRevision': '$revision',
            'anchor': op['kind'] == 'DELETE'
                ? null
                : _anchor(target, anchors[target]!),
            'replayed': false,
          });
        }
        return _data('constellationAnchorsApply', {
          '__typename': 'v2_ConstellationAnchorsApplyResult',
          'beforeRevision': '$before',
          'afterRevision': '$revision',
          'results': results,
        });
      default:
        throw StateError('Unexpected operation: ${body['operationName']}');
    }
  });

  http.Response _data(String field, Object value) => _response({
    'data': {field: value},
  });

  http.Response _response(Map<String, Object?> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

class LayoutHistorySnapshot {
  const LayoutHistorySnapshot({
    required this.id,
    required this.kind,
    required this.reason,
    required this.createdAt,
    required this.anchors,
  });

  final String id;
  final int kind;
  final int reason;
  final DateTime createdAt;
  final Map<ConstellationAnchorTarget, ConstellationAnchorPosition> anchors;

  Map<String, Object?> get wire => {
    '__typename': 'v2_ConstellationLayoutSnapshot',
    'id': id,
    'kind': kind,
    'reason': reason,
    'anchorCount': anchors.length,
    'anchors': [
      for (final e in anchors.entries)
        {
          '__typename': 'v2_ConstellationLayoutSnapshotAnchor',
          'targetKind': e.key.kind.name.toUpperCase(),
          'targetId': e.key.id,
          'xUnits': e.value.xUnits,
          'yUnits': e.value.yUnits,
          'coordinateSpaceVersion': e.value.coordinateSpaceVersion,
        },
    ],
    'createdAt': createdAt.toIso8601String(),
  };
}

class _FieldRepository implements ConstellationRepositoryPort {
  _FieldRepository(this.server);
  final LayoutHistoryServer server;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    const peers = [
      ConstellationPerson(id: 'p1', displayName: 'Peer one'),
      ConstellationPerson(id: 'p2', displayName: 'Peer two'),
      ConstellationPerson(id: 'p3', displayName: 'Peer three'),
      ConstellationPerson(id: 'p4', displayName: 'Peer four'),
    ];
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 25),
      context: '',
      peers: peers,
      directContactIds: peers.map((p) => p.id).toList(),
      edges: [
        for (final p in peers)
          ConstellationTrustEdgeEntity(src: 'ego', dst: p.id, tier: 1),
      ],
      anchorProjection: ConstellationAnchorProjection(
        revision: arrangeRevision(server.revision),
        anchors: [
          for (final e in server.anchors.entries)
            ConstellationAnchor(
              target: e.key,
              position: e.value,
              revision: arrangeRevision(server.revision),
              placedAt: DateTime.utc(2026, 10, 25),
            ),
        ],
        pinnedPeers: peers,
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );
  }
}

typedef LayoutHistoryHarness = ({
  ConstellationCubit cubit,
  ConstellationPlacementCase placement,
  FakeClockPort clock,
});

Future<LayoutHistoryHarness> layoutHistoryHarness(LayoutHistoryServer server) =>
    http.runWithClient(() async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      addTearDown(remote.close);
      await remote.setSessionAuth();
      // Session authentication is lazy. Fetch the token while the HTTP client
      // factory is still scoped to this server, before widget actions run.
      await remote.getAuthToken();
      final clock = FakeClockPort(DateTime.utc(2026, 10, 25, 12));
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      final store = ConstellationStoreFixture(
        _FieldRepository(server),
        accountId: 'ego',
        clock: clock,
        realtime: sync.case_,
      ).store;
      final placement = ConstellationPlacementCase(
        ConstellationAnchorRepository(remote),
        store,
        clock,
        FakeWakeUpPort(),
        realtime: sync.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('LayoutHistoryTest'),
      );
      final cubit = ConstellationCubit(
        case_: store,
        viewer: const Profile(id: 'ego', displayName: 'Ego'),
        anchorCase: ConstellationAnchorCase(
          env: const Env.fromEnvironment(),
          logger: Logger('LayoutHistoryTest'),
        ),
        placementCase: placement,
        loadOnCreate: false,
      );
      addTearDown(() async {
        await cubit.close();
        await placement.dispose();
      });
      await cubit.load();
      return (cubit: cubit, placement: placement, clock: clock);
    }, () => server.client);
