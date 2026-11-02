@Tags(['pg', 'repo-files'])
library;

// Coverage map for Request update receipts and discussion typing:
// - Opening the visible next step: real Ferry -> repository -> case -> cubit
//   -> Now surface; helper and steward send exactly one mark per revision.
// - Author's open page: production GraphQL/PG transport plus independent
//   client sessions, live count 1/2/3;
//   author and non-admitted recipient send no mark; new step clears the row.
// - Stored receipt + author socket invalidation + rejected outsider: the new
//   focused test in request_update_seen_by_graphql_pg_test.dart (real PG).
// - Phone/RU typing geometry: room_typing_message_visibility_test.dart.
// - Reader sheet names/times, cold load, privacy and new-step reset remain
//   covered in request_update_seen_by_row_test.dart and the existing PG tests.
// - Typing relay/count/expiry/stop/send/self/outsider: existing room_typing_*
//   tests and room_typing_relay_pg_test.dart; this task does not change them.
// - Browser accessibility and viewport: test/
//   room_typing_message_visibility_web_test.dart runs the same geometry check
//   with widget semantics and the browser's exported accessibility DOM.
// Sibling matrix:
// role: author / admitted helper / steward / non-admitted -> tests below + PG.
// surface: Request -> mark-on-open/count; discussion -> typing geometry.
// freshness: live -> below + PG; after reload -> existing row/PG tests.
// width/locale: desktop EN -> single-view tests; 375x667 RU -> live author
//   test and typing geometry; the browser target checks the exported label.
// No browser focus/touch/keyboard claim is made by these wire/widget tests.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/phone_surface.dart';
import '../../support/production_receipt_transport.dart';
import '../beacon_threads/support/room_typing_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _beaconId = 'Bseenby000001';
const _authorId = 'Ua00000000001';
const _helperId = 'Ua00000000003';
const _stewardId = 'Ua00000000002';
const _furtherHelperId = 'Ua00000000004';
const _outsiderId = 'Ua00000000005';
const _step = 'Bring the ladder';
const _revisedStep = 'Move the sofa';

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepo implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _HarnessRouter extends Mock implements StackRouter {}

/// One reader row as the server's `BeaconUpdateReader` type returns it.
Map<String, dynamic> _reader(String id, String title) => {
  '__typename': 'v2_BeaconUpdateReader',
  'userId': id,
  'seenAt': '2026-10-30T10:00:00.000Z',
  'userTitle': title,
  'userHasPicture': false,
  'userImageId': '',
  'userBlurHash': '',
  'userPicHeight': 0,
  'userPicWidth': 0,
};

// Mutable server responses shared by independent signed-in clients. The mark
// writes a receipt and sends the existing Request entity-change envelope.
// No test calls a repository mark method: viewing the Request must cause it.
class _Server {
  String line = _step;
  int revision = 1;
  DateTime updatedAt = DateTime.utc(2026, 10, 30, 9);
  final readers = <Map<String, dynamic>>[];
  final marks = <({String viewer, int revision, Object? beaconId})>[];
  final sockets = <String, RoomTypingWireSocket>{};
  int readersRequests = 0;
  final readerRequestsByViewer = <String, int>{};
  final admitted = {_helperId, _stewardId, _furtherHelperId};
  bool autoPublishMarks = true;
  int pendingMarkInvalidations = 0;
  Completer<void>? receiptGate;

  void flushMarkInvalidations() {
    expect(pendingMarkInvalidations, greaterThan(0));
    pendingMarkInvalidations = 0;
    invalidate();
  }

  void invalidate() {
    for (final entry in sockets.entries) {
      if (entry.key != _authorId && !admitted.contains(entry.key)) continue;
      entry.value.frames.add(
        jsonEncode({
          'type': 'subscription',
          'path': 'entity_changes',
          'payload': {
            'entity': 'beacon',
            'id': _beaconId,
            'event': 'update',
            'actor_user_id': null,
            'room_state': true,
          },
        }),
      );
    }
  }

  Future<http.Response> handle(http.Request request, String viewer) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return _json({
        'subject': viewer,
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final query = body['query'] as String? ?? '';
    final variables = (body['variables'] as Map?) ?? const {};
    final data = <String, dynamic>{};
    if (query.contains('MarkBeaconUpdateSeen(')) {
      marks.add((
        viewer: viewer,
        revision: revision,
        beaconId: variables['beaconId'],
      ));
      if (variables['beaconId'] != _beaconId) {
        return _json({
          'data': null,
          'errors': [
            {
              'message': 'Unknown Request',
              'extensions': {'code': '1001'},
            },
          ],
        });
      }
      if (viewer != _authorId && !admitted.contains(viewer)) {
        return _json({
          'data': null,
          'errors': [
            {
              'message': 'Room access required',
              'extensions': {'code': '1102'},
            },
          ],
        });
      }
      // Holding this response lets the author observe the cleared list for a
      // new step before an already-open helper's second receipt is stored.
      final gate = receiptGate;
      if (gate != null) await gate.future;
      if (!readers.any((row) => row['userId'] == viewer)) {
        readers.add(_reader(viewer, viewer));
      }
      data['MarkBeaconUpdateSeen'] = {
        '__typename': 'v2_BeaconUpdateSeenResult',
        'beaconId': _beaconId,
        'seenAt': DateTime.utc(2026, 10, 30, 10).toIso8601String(),
      };
      if (autoPublishMarks) {
        invalidate();
      } else {
        pendingMarkInvalidations++;
      }
    }
    if (query.contains('BeaconRoomStateGet(')) {
      data['BeaconRoomStateGet'] = {
        '__typename': 'v2_BeaconRoomStateRow',
        'beaconId': _beaconId,
        'currentLine': line,
        'currentLineRevision': revision,
        'openBlockerId': null,
        'openBlockerTitle': null,
        'lastRoomMeaningfulChange': null,
        'updatedAt': updatedAt.toIso8601String(),
        'updatedBy': _authorId,
      };
    }
    if (query.contains('BeaconParticipantList(')) {
      data['BeaconParticipantList'] = [
        for (final (id, role, access) in [
          (
            _helperId,
            BeaconParticipantRoleBits.helper,
            RoomAccessBits.admitted,
          ),
          (
            _stewardId,
            BeaconParticipantRoleBits.steward,
            RoomAccessBits.admitted,
          ),
          (
            _furtherHelperId,
            BeaconParticipantRoleBits.helper,
            RoomAccessBits.admitted,
          ),
          (_outsiderId, BeaconParticipantRoleBits.helper, RoomAccessBits.none),
        ])
          {
            '__typename': 'v2_BeaconParticipantRow',
            'id': 'P$id',
            'beaconId': _beaconId,
            'userId': id,
            'userTitle': id,
            'userHandle': '',
            'userHasPicture': false,
            'userPicHeight': 0,
            'userPicWidth': 0,
            'userBlurHash': '',
            'userImageId': '',
            'role': role,
            'status': 0,
            'roomAccess': access,
            'createdAt': '2026-10-30T08:00:00.000Z',
            'updatedAt': '2026-10-30T08:00:00.000Z',
          },
      ];
    }
    if (query.contains('beaconUpdateSeenBy')) {
      readersRequests++;
      readerRequestsByViewer.update(
        viewer,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      data['beaconUpdateSeenBy'] = viewer == _authorId || viewer == _stewardId
          ? readers
          : <Map<String, dynamic>>[];
    }
    return _json({'data': data.isEmpty ? null : data});
  }

  http.Response _json(Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

// The production variant forwards Ferry's HTTP body to the server-package
// process and injects only bytes emitted by its real PostgreSQL fanout. None
// of _Server's simulated storage, refusal or publisher is used in these tests.
class _ProductionServer extends _Server {
  _ProductionServer(this.transport) {
    _frames = transport.frames.listen((event) {
      receivedFrames.add(event);
      sockets[event.viewer]?.frames.add(jsonEncode(event.frame));
    });
  }
  final ProductionReceiptTransport transport;
  late final StreamSubscription<({String viewer, Object frame})> _frames;
  final receivedFrames = <({String viewer, Object frame})>[];

  static Future<_ProductionServer> start() async =>
      _ProductionServer(await ProductionReceiptTransport.start());

  @override
  void invalidate() => throw StateError(
    'Production scenarios require real PostgreSQL invalidation',
  );

  @override
  Future<http.Response> handle(http.Request request, String viewer) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': viewer,
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final query = body['query'] as String;
    if (query.contains('beaconUpdateSeenBy')) {
      readersRequests++;
      readerRequestsByViewer.update(
        viewer,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    if (query.contains('MarkBeaconUpdateSeen(')) {
      marks.add((
        viewer: viewer,
        revision: revision,
        beaconId: (body['variables'] as Map?)?['beaconId'],
      ));
    }
    final response = await transport.graphql(viewer, body);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final room = (decoded['data'] as Map?)?['BeaconRoomStateGet'] as Map?;
    if (room != null) {
      line = room['currentLine'] as String;
      revision = room['currentLineRevision'] as int;
      updatedAt = DateTime.parse(room['updatedAt'] as String);
    }
    return response;
  }

  Future<Map<String, dynamic>> execute(
    String viewer,
    String query,
    Map<String, dynamic> variables,
  ) async {
    final response = await transport.graphql(viewer, {
      'query': query,
      'variables': variables,
    });
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(
      body['errors'],
      isNull,
      reason: 'the production schema must accept the action',
    );
    return body['data'] as Map<String, dynamic>;
  }

  Future<List<String>> storedReaders() async {
    final data = await execute(
      _authorId,
      r'''
      query ActualReaders($id: String!) {
        beaconUpdateSeenBy(id: $id) { userId seenAt }
      }
    ''',
      {'id': _beaconId},
    );
    return [
      for (final row in data['beaconUpdateSeenBy'] as List)
        (row as Map)['userId'] as String,
    ];
  }

  Future<void> markThroughApi(String viewer) async {
    await execute(
      viewer,
      r'''
      mutation MarkBeaconUpdateSeen($beaconId: String!) {
        MarkBeaconUpdateSeen(beaconId: $beaconId) { beaconId seenAt }
      }
    ''',
      {'beaconId': _beaconId},
    );
  }

  Future<void> reviseThroughApi(String nextStep) async {
    final data = await execute(
      _authorId,
      r'''
      mutation Revise($beaconId: String!, $text: String!, $baseRevision: Int!) {
        BeaconRoomNowLineUpdate(beaconId: $beaconId, text: $text, baseRevision: $baseRevision) {
          updatedAt currentLineRevision
        }
      }
    ''',
      {'beaconId': _beaconId, 'text': nextStep, 'baseRevision': revision},
    );
    final result = data['BeaconRoomNowLineUpdate'] as Map;
    line = nextStep;
    revision = result['currentLineRevision'] as int;
    updatedAt = DateTime.parse(result['updatedAt'] as String);
  }

  Future<void> dispose() async {
    await _frames.cancel();
    await transport.close();
  }
}

final class _SocketFactory implements RealtimeSocketFactory {
  _SocketFactory(this.socket);
  final RoomTypingWireSocket socket;
  @override
  RealtimeSocket create(Uri uri) => socket;
}

// Only unrelated Request metadata is stubbed. Invalidation subscription and
// repository event delivery use the real BeaconRepository constructor.
class _BeaconRepository extends BeaconRepository {
  _BeaconRepository(super._remoteApiService, super.realtimeSync, this.server);
  final _Server server;
  @override
  Future<Beacon> fetchBeaconById(String id) async =>
      _beacon(updatedAt: server.updatedAt);
  @override
  Future<List<Profile>> fetchAdmittedHelpers(String id) async => const [];
}

class _Session {
  _Session(this.cubit, this.server, this._tester);
  final BeaconViewCubit cubit;
  final _Server server;
  final WidgetTester _tester;

  Future<void> reviseNextStep(String line) => _tester.runAsync(() async {
    server
      ..line = line
      ..revision += 1
      ..updatedAt = server.updatedAt.add(const Duration(minutes: 1));
    server.readers.clear();
    server.invalidate();
    await _until(() => cubit.state.beaconRoomCue?.currentLine == line);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
}

Beacon _beacon({DateTime? updatedAt}) => Beacon(
  id: _beaconId,
  title: 'Moving day',
  createdAt: DateTime.utc(2026, 10),
  updatedAt: updatedAt ?? DateTime.utc(2026, 10),
  author: const Profile(id: _authorId, displayName: 'Author'),
);

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline) && !condition()) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Opens the Request view as [viewer] against [server] and returns once the
/// view has loaded and had the chance to ask for the readers. The wire stays
/// open until the test ends so later refreshes work.
Future<_Session> _openRequestView(
  WidgetTester tester, {
  required Profile viewer,
  required _Server server,
}) async {
  late _Session session;
  await tester.runAsync(
    () => http.runWithClient(() async {
      final socket = RoomTypingWireSocket();
      server.sockets[viewer.id] = socket;
      final remote = RemoteApiService(const Env(), _SocketFactory(socket));
      await remote.setSessionAuth();
      await remote.bindRealtimeAccount(viewer.id);
      socket.connections.add(RealtimeSocketConnectionState.connected);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      socket.frames.add(
        jsonEncode({
          'type': 'auth',
          'intent': 'sign_in',
          'result': 'success',
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      addTearDown(remote.close);
      final invalidation = InvalidationService(remote);
      addTearDown(invalidation.dispose);
      final realtime = RealtimeSyncCase(invalidation);
      final roomRepository = BeaconThreadsRepository(remote, invalidation);
      addTearDown(roomRepository.dispose);
      final threads = BeaconThreadsCase(
        roomRepository,
        FakeBeaconViewFactCardRepository(),
        FakeBeaconViewPollingRepository(),
        FakeBeaconViewRoomHintsRepository(),
        RoomReadWatermarkStore.testing(),
        realtime,
        env: const Env(),
        logger: Logger('test'),
      );
      final beaconRepo = _BeaconRepository(remote, invalidation, server);
      addTearDown(beaconRepo.dispose);
      final viewCase = BeaconViewCase(
        beaconRepo,
        FakeBeaconViewForwardRepository(),
        FakeBeaconViewClosureRepository(),
        FakeBeaconViewArchiveRepository(),
        FakeBeaconViewCoordinationRepository(),
        FakeBeaconDisplayRepository(),
        FakeBeaconViewInboxRepository(),
        FakeBeaconViewPostsRepository(),
        FakeBeaconViewFactCardRepository(),
        threads,
        FakeBeaconViewActivityEventRepository(),
        realtime,
        env: const Env(),
        logger: Logger('test'),
        presenceRepository: quietTestPresenceRepository(),
      );
      final cubit = BeaconViewCubit(
        id: _beaconId,
        myProfile: viewer,
        beaconViewCase: viewCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      await _until(
        () =>
            cubit.state.beaconContextLoaded &&
            cubit.state.beaconRoomCue != null &&
            server.readersRequests > 0,
      );
      expect(cubit.state.beaconContextLoaded, isTrue);
      expect(cubit.state.beaconRoomCue?.currentLine, server.line);
      expect(server.readersRequests, greaterThan(0));
      // Let the answer to the last request reach the cubit.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      session = _Session(cubit, server, tester);
    }, () => MockClient((request) => server.handle(request, viewer.id))),
  );
  return session;
}

Future<void> _pumpNowSurface(
  WidgetTester tester,
  BeaconViewCubit cubit, {
  Locale locale = const Locale('en'),
}) async {
  final hierarchyCubit = BeaconHierarchyCubit(
    beaconId: _beaconId,
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      FakeBeaconHierarchyRepositoryPort(
        capabilities: const BeaconHierarchyCapabilities(
          canListChildren: false,
          canCreateChild: false,
        ),
      ),
      createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
      beacons: _NoopBeaconWritePort(),
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
  );
  addTearDown(hierarchyCubit.close);
  final screenCubit = ScreenCubit.local();
  addTearDown(screenCubit.close);

  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: locale,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(
              value: _MockProfileCubit(cubit.state.myProfile),
            ),
            BlocProvider<BeaconHierarchyCubit>.value(value: hierarchyCubit),
          ],
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconNowSurface(
                beaconViewCubit: cubit,
                screenCubit: screenCubit,
                beaconState: cubit.state,
                onSurfaceSelected: (_) {},
                onActivatePeopleTabAttention: () {},
                onFocusCoordinationItem: (_) {},
                onOpenGeneralThread: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _text(String text) => find.text(text, findRichText: true);

Finder _textContaining(String text) =>
    find.textContaining(text, findRichText: true);

void main() {
  group('Live receipts through production GraphQL and PostgreSQL', () {
    Future<_ProductionServer> start(WidgetTester tester) async {
      final server = (await tester.runAsync(_ProductionServer.start))!;
      addTearDown(() => tester.runAsync(server.dispose));
      return server;
    }

    testWidgets(
      'viewing helpers update the open author page through production notifications',
      (tester) async {
        await usePhoneSurface(tester);
        final server = await start(tester);
        final author = await _openRequestView(
          tester,
          viewer: const Profile(id: _authorId, displayName: 'Автор'),
          server: server,
        );
        await _pumpNowSurface(tester, author.cubit, locale: const Locale('ru'));
        expect(_textContaining(_step), findsOneWidget);
        final viewers = <String>[];
        for (final viewer in [_helperId, _furtherHelperId, _stewardId]) {
          final helper = await _openRequestView(
            tester,
            viewer: Profile(id: viewer, displayName: viewer),
            server: server,
          );
          expect(helper.cubit.state.beaconRoomCue?.currentLine, _step);
          expect(helper.cubit.state.canCoordinateInBeaconRoom, isTrue);
          await tester.runAsync(
            () =>
                _until(() => server.marks.any((mark) => mark.viewer == viewer)),
          );
          expect(
            server.marks.where((mark) => mark.viewer == viewer),
            hasLength(1),
            reason:
                'opening the Request must send its mark to the production mutation',
          );
          viewers.add(viewer);
          final stored = await tester.runAsync(server.storedReaders);
          expect(stored, unorderedEquals(viewers));
          await tester.runAsync(
            () => _until(
              () =>
                  author.cubit.state.latestUpdateReaders.length ==
                  viewers.length,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            _text('Видели: ${viewers.length}'),
            findsOneWidget,
            reason:
                'only the production PostgreSQL fanout can update this open author page',
          );
        }
      },
    );

    testWidgets(
      'committed helper receipts refresh the open author count through real server invalidations',
      (tester) async {
        await usePhoneSurface(tester);
        final server = await start(tester);
        final author = await _openRequestView(
          tester,
          viewer: const Profile(id: _authorId, displayName: 'Автор'),
          server: server,
        );
        await _pumpNowSurface(tester, author.cubit, locale: const Locale('ru'));
        expect(_textContaining(_step), findsOneWidget);
        expect(_textContaining('Видели:'), findsNothing);
        final viewers = <String>[];
        for (final viewer in [_helperId, _furtherHelperId, _stewardId]) {
          final readsBefore = server.readerRequestsByViewer[_authorId]!;
          await tester.runAsync(() => server.markThroughApi(viewer));
          viewers.add(viewer);
          final stored = await tester.runAsync(server.storedReaders);
          expect(
            stored,
            unorderedEquals(viewers),
            reason: 'the production mutation committed the view',
          );
          await tester.runAsync(
            () => _until(
              () =>
                  author.cubit.state.latestUpdateReaders.length ==
                  viewers.length,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            _text('Видели: ${viewers.length}'),
            findsOneWidget,
            reason:
                'a committed view must become visible without reloading the author page',
          );
          expect(
            server.readerRequestsByViewer[_authorId],
            greaterThan(readsBefore),
          );
          expect(
            server.receivedFrames.where((event) => event.viewer == _authorId),
            isNotEmpty,
          );
        }
        await tester.runAsync(() => server.reviseThroughApi(_revisedStep));
        await tester.runAsync(
          () => _until(
            () => author.cubit.state.beaconRoomCue?.currentLine == _revisedStep,
          ),
        );
        await tester.pumpAndSettle();
        expect(_textContaining(_revisedStep), findsOneWidget);
        expect(_textContaining('Видели:'), findsNothing);
        expect(await tester.runAsync(server.storedReaders), isEmpty);
      },
    );
  });

  group('Viewing the current Request update', () {
    for (final (role, id) in [('helper', _helperId), ('steward', _stewardId)]) {
      testWidgets(
        'an admitted $role records one view per update despite live refreshes',
        (tester) async {
          final server = _Server();
          final session = await _openRequestView(
            tester,
            viewer: Profile(id: id, displayName: role),
            server: server,
          );
          await _pumpNowSurface(tester, session.cubit);
          expect(_textContaining(_step), findsOneWidget);
          expect(session.cubit.state.roomParticipantsLoaded, isTrue);
          expect(session.cubit.state.canCoordinateInBeaconRoom, isTrue);
          await tester.runAsync(() async {
            server.invalidate();
            await Future<void>.delayed(const Duration(milliseconds: 600));
          });
          await tester.pumpAndSettle();
          expect(
            server.marks.where(
              (mark) => mark.viewer == id && mark.revision == 1,
            ),
            hasLength(1),
            reason: 'seeing the next step sends exactly one mark',
          );
          expect(server.marks.single.beaconId, _beaconId);
          if (id == _helperId) {
            expect(
              _textContaining('Seen by'),
              findsNothing,
              reason: 'an ordinary helper cannot read the readers list',
            );
          }

          await session.reviseNextStep(_revisedStep);
          await tester.pumpAndSettle();
          expect(_textContaining(_revisedStep), findsOneWidget);
          expect(
            server.marks.where(
              (mark) => mark.viewer == id && mark.revision == 2,
            ),
            hasLength(1),
          );
          expect(server.marks, hasLength(2));
        },
      );
    }

    testWidgets(
      'the author refetches live counts only after receipt invalidation and an open helper marks the revised update once',
      (tester) async {
        await usePhoneSurface(tester);
        final server = _Server()..autoPublishMarks = false;
        final author = await _openRequestView(
          tester,
          viewer: const Profile(id: _authorId, displayName: 'Автор'),
          server: server,
        );
        await _pumpNowSurface(tester, author.cubit, locale: const Locale('ru'));
        expect(_textContaining(_step), findsOneWidget);
        expect(_textContaining('Видели:'), findsNothing);

        final helpers = <BeaconViewCubit>[];
        for (final (index, viewer) in [
          _helperId,
          _stewardId,
          _furtherHelperId,
        ].indexed) {
          final readsBefore = server.readerRequestsByViewer[_authorId]!;
          final helper = await _openRequestView(
            tester,
            viewer: Profile(id: viewer, displayName: viewer),
            server: server,
          );
          helpers.add(helper.cubit);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 600)),
          );
          await tester.pumpAndSettle();
          expect(
            server.marks.where(
              (mark) => mark.viewer == viewer && mark.revision == 1,
            ),
            hasLength(1),
            reason: 'opening the Request must send one mark',
          );
          expect(server.readers, hasLength(index + 1));
          expect(
            server.readerRequestsByViewer[_authorId],
            readsBefore,
            reason:
                'the author cannot learn about a stored view before its socket hint',
          );
          if (index == 0) {
            expect(_textContaining('Видели:'), findsNothing);
          } else {
            expect(_text('Видели: $index'), findsOneWidget);
          }

          await tester.runAsync(() async {
            server.flushMarkInvalidations();
            await _until(
              () => author.cubit.state.latestUpdateReaders.length == index + 1,
            );
          });
          await tester.pumpAndSettle();
          expect(
            server.readerRequestsByViewer[_authorId],
            greaterThan(readsBefore),
            reason:
                'the socket hint must cause a real BeaconUpdateSeenBy refetch',
          );
          expect(_text('Видели: ${index + 1}'), findsOneWidget);
        }
        expect(server.marks.where((mark) => mark.viewer == _authorId), isEmpty);
        final outsider = await _openRequestView(
          tester,
          viewer: const Profile(id: _outsiderId, displayName: 'Recipient'),
          server: server,
        );
        expect(outsider.cubit.state.roomParticipantsLoaded, isTrue);
        expect(
          server.marks.where((mark) => mark.viewer == _outsiderId),
          isEmpty,
          reason:
              'even a refused mark attempt must not be sent by a non-admitted client',
        );
        expect(server.readers, hasLength(3));

        // Keep the first helper open across revisions in this same live-author
        // scenario. The other viewers have left before the new next step.
        await tester.runAsync(() async {
          for (final helper in helpers.skip(1)) {
            await helper.close();
          }
          await outsider.cubit.close();
        });
        final gate = Completer<void>();
        server.receiptGate = gate;
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        await author.reviseNextStep(_revisedStep);
        await tester.pumpAndSettle();
        expect(_textContaining(_revisedStep), findsOneWidget);
        expect(
          _textContaining('Видели:'),
          findsNothing,
          reason: 'old viewers disappear live before the new receipt is stored',
        );
        expect(server.readers, isEmpty);
        await tester.runAsync(
          () => _until(
            () => server.marks.any(
              (mark) => mark.viewer == _helperId && mark.revision == 2,
            ),
          ),
        );
        expect(
          server.marks.where(
            (mark) => mark.viewer == _helperId && mark.revision == 2,
          ),
          hasLength(1),
          reason:
              'the helper still viewing the page sees the revised update once',
        );
        final readsBeforeNewReceipt = server.readerRequestsByViewer[_authorId]!;
        gate.complete();
        await tester.runAsync(
          () => _until(() => server.pendingMarkInvalidations > 0),
        );
        await tester.pumpAndSettle();
        expect(server.readers.map((row) => row['userId']), [_helperId]);
        expect(_textContaining('Видели:'), findsNothing);
        expect(server.readerRequestsByViewer[_authorId], readsBeforeNewReceipt);
        await tester.runAsync(() async {
          server.flushMarkInvalidations();
          await _until(
            () => author.cubit.state.latestUpdateReaders.length == 1,
          );
          server.invalidate();
          await Future<void>.delayed(const Duration(milliseconds: 600));
        });
        await tester.pumpAndSettle();
        expect(_text('Видели: 1'), findsOneWidget);
        expect(
          server.readerRequestsByViewer[_authorId],
          greaterThan(readsBeforeNewReceipt),
        );
        expect(
          server.marks.where(
            (mark) => mark.viewer == _helperId && mark.revision == 1,
          ),
          hasLength(1),
        );
        expect(
          server.marks.where(
            (mark) => mark.viewer == _helperId && mark.revision == 2,
          ),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
