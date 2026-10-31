// "Seen by N" on a Request's latest next step / status update (#766).
//
// The Request view asks the server who has seen the latest update (the V2
// query field `beaconUpdateSeenBy(id)`, whose reader type is
// `BeaconUpdateReader`) and, when the server names readers, shows a
// "Seen by N" row next to the next step; tapping it lists the people. The
// server returns the list only to the update's author and the Request's
// author / stewards and an empty list to everyone else, so the client shows
// exactly what it is told: an empty answer (or a failed lookup) is no row at
// all, whoever the viewer is, and a non-empty answer is a row, whoever the
// viewer is.
//
// Everything below runs the real path: a real `RemoteApiService` over the
// real Ferry link chain (only the HTTP transport is faked), the real
// `BeaconThreadsRepository`, `BeaconViewCase` and `BeaconViewCubit`, and the
// real `BeaconNowSurface` widget. The fake server recognises requests by the
// root fields they select, not by operation name, so the client's own naming
// of the operation is free; the field, type and reader field names are the
// ones the server defines (packages/server custom_types.dart).
//
// Not covered here: touch, keyboard focus and semantics of the row. Per the
// evidence rule those are proven by the web integration_test
// (scripts/run_client_integration_web_local.sh), not by a widget test.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
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
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _beaconId = 'Bseenby000001';
const _authorId = 'Uauthor000001';
const _helperId = 'Uhelper000001';
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

/// The fake backend. It answers `BeaconRoomStateGet` (the next step) and
/// `beaconUpdateSeenBy` (the readers) from mutable state, so a test can change
/// what the server says between two refreshes.
class _Server {
  String line = _step;
  int revision = 1;
  DateTime updatedAt = DateTime.utc(2026, 10, 30, 9);
  List<Map<String, dynamic>> readers = [];

  /// When set, the readers lookup fails with this GraphQL error.
  Map<String, dynamic>? readersError;

  /// When set, the readers answer is held back until it completes.
  Completer<void>? readersGate;

  final queries = <String>[];
  final readersVariables = <Map<String, dynamic>>[];

  bool _asksReaders(String query) => query.contains('beaconUpdateSeenBy');

  int get readersRequests => queries.where(_asksReaders).length;

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return _json({
        'subject': 'Uviewer000001',
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final query = body['query'] as String? ?? '';
    queries.add(query);
    if (_asksReaders(query)) {
      readersVariables.add(
        ((body['variables'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
    }

    final data = <String, dynamic>{'__typename': 'query_root'};
    var answered = false;
    if (query.contains('BeaconRoomStateGet(')) {
      answered = true;
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
    if (_asksReaders(query)) {
      final gate = readersGate;
      if (gate != null) await gate.future;
      final error = readersError;
      if (error != null) {
        return _json({
          'data': null,
          'errors': [error],
        });
      }
      answered = true;
      data['beaconUpdateSeenBy'] = readers;
    }
    return _json({'data': answered ? data : null});
  }

  http.Response _json(Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

class _Session {
  _Session(this.cubit, this.server, this.beaconRepo, this._tester);

  final BeaconViewCubit cubit;
  final _Server server;
  final TrackingBeaconRepository beaconRepo;
  final WidgetTester _tester;

  /// The Request changed live (someone saved a new next step): the server
  /// says [line] now, and the push reaches the open Request view. Returns
  /// once the view shows the new next step and has had time to settle.
  Future<void> reviseNextStep(String line) => _tester.runAsync(() async {
    server
      ..line = line
      ..revision += 1
      ..updatedAt = DateTime.utc(2026, 10, 30, 9, 30);
    beaconRepo.emitUpdate(_beacon(updatedAt: server.updatedAt));
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
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      await remote.setSessionAuth();
      addTearDown(remote.close);

      final realtime = buildTestRealtimeSync();
      final threads = BeaconThreadsCase(
        BeaconThreadsRepository(remote, realtime.port),
        FakeBeaconViewFactCardRepository(),
        FakeBeaconViewPollingRepository(),
        FakeBeaconViewRoomHintsRepository(),
        RoomReadWatermarkStore.testing(),
        realtime.case_,
        env: const Env(),
        logger: Logger('test'),
      );
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _beacon(updatedAt: server.updatedAt);
      final viewCase = BeaconViewCase(
        beaconRepo,
        FakeBeaconViewForwardRepository(),
        FakeBeaconViewClosureRepository(),
        FakeBeaconViewArchiveRepository(),
        FakeBeaconViewCoordinationRepository(),
        FakeBeaconDisplayRepository(),
        FakeBeaconViewInboxRepository(),
        FakeBeaconViewFactCardRepository(),
        threads,
        FakeBeaconViewActivityEventRepository(),
        buildTestRealtimeSync().case_,
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
      // Let the answer to the last request reach the cubit.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      session = _Session(cubit, server, beaconRepo, tester);
    }, () => MockClient(server.handle)),
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

String _plain(Widget w) => w is RichText ? w.text.toPlainText() : '';

/// Everything the screen currently says, one string per paragraph.
Set<String> _allText(WidgetTester tester) => {
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) _plain(w),
};

void main() {
  const author = Profile(id: _authorId, displayName: 'Author');
  const helper = Profile(id: _helperId, displayName: 'Helper');

  group('Seen by row with readers', () {
    // The visible count and the listed names come from the server's answer:
    // other counts and other names give other rows.
    for (final (names, label) in [
      (['Alice', 'Bob'], 'Seen by 2'),
      (['Chen', 'Dana', 'Eli'], 'Seen by 3'),
      (['Fay'], 'Seen by 1'),
    ]) {
      testWidgets(
        'the Request author sees "$label" next to the next step and, on tap, '
        'the name of each of the ${names.length} reader(s)',
        (tester) async {
          final server = _Server()
            ..readers = [
              for (final (i, n) in names.indexed) _reader('Ureader00000$i', n),
            ];
          final session = await _openRequestView(
            tester,
            viewer: author,
            server: server,
          );
          // The next step itself is what the row is about.
          expect(
            beaconHudNowLine(
              lookupL10n(const Locale('en')),
              session.cubit.state,
            ),
            _step,
          );

          await _pumpNowSurface(tester, session.cubit);

          expect(_textContaining(_step), findsOneWidget);
          expect(_text(label), findsOneWidget);
          for (final n in names) {
            expect(_text(n), findsNothing, reason: 'names show on tap');
          }

          await tester.tap(_text(label));
          await tester.pumpAndSettle();

          for (final n in names) {
            expect(_text(n), findsOneWidget);
          }
        },
      );
    }

    testWidgets('a steward who is neither the Request author nor the update '
        'author sees the row the server gave them', (tester) async {
      final server = _Server()..readers = [_reader('Ualice000001', 'Alice')];
      final session = await _openRequestView(
        tester,
        viewer: helper,
        server: server,
      );

      await _pumpNowSurface(tester, session.cubit);

      expect(_text('Seen by 1'), findsOneWidget);
    });
  });

  group('Seen by row without readers', () {
    for (final (who, viewer) in [
      ('the Request author', author),
      ('another member', helper),
    ]) {
      testWidgets('$who sees no "Seen by" row when the server names no '
          'readers, though the view asked for them', (tester) async {
        final server = _Server();
        final session = await _openRequestView(
          tester,
          viewer: viewer,
          server: server,
        );
        expect(
          server.readersRequests,
          greaterThan(0),
          reason: 'the client asks; the server decides who may know',
        );
        expect(
          server.readersVariables,
          everyElement(
            predicate<Map<String, dynamic>>(
              (v) => v.values.contains(_beaconId),
              'carries the Request id',
            ),
          ),
        );

        await _pumpNowSurface(tester, session.cubit);

        expect(_textContaining(_step), findsOneWidget);
        expect(_textContaining('Seen by'), findsNothing);
      });
    }

    testWidgets('a failed readers lookup shows no "Seen by" row and keeps the '
        'next step on screen', (tester) async {
      final server = _Server()
        ..readers = [_reader('Ualice000001', 'Alice')]
        ..readersError = {'message': 'Internal server error'};
      final session = await _openRequestView(
        tester,
        viewer: author,
        server: server,
      );
      expect(
        server.readersRequests,
        greaterThan(0),
        reason:
            'the lookup must have been attempted for this to prove '
            'anything',
      );

      await _pumpNowSurface(tester, session.cubit);

      expect(_textContaining(_step), findsOneWidget);
      expect(_textContaining('Seen by'), findsNothing);
    });
  });

  group('Seen by row over time', () {
    testWidgets('while the readers are still loading the next step shows '
        'without a row, and the row appears when they arrive', (tester) async {
      final server = _Server()
        ..readers = [
          _reader('Ualice000001', 'Alice'),
          _reader('Ubob0000001', 'Bob'),
        ]
        ..readersGate = Completer<void>();
      final session = await _openRequestView(
        tester,
        viewer: author,
        server: server,
      );
      expect(server.readersRequests, greaterThan(0));

      await _pumpNowSurface(tester, session.cubit);
      expect(_textContaining(_step), findsOneWidget);
      expect(_textContaining('Seen by'), findsNothing);
      expect(tester.takeException(), isNull);

      server.readersGate!.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();

      expect(_text('Seen by 2'), findsOneWidget);
    });

    testWidgets('when the next step is revised the row follows the new update '
        'instead of keeping the old readers', (tester) async {
      final server = _Server()
        ..readers = [
          _reader('Ualice000001', 'Alice'),
          _reader('Ubob0000001', 'Bob'),
        ];
      final session = await _openRequestView(
        tester,
        viewer: author,
        server: server,
      );
      await _pumpNowSurface(tester, session.cubit);
      expect(_text('Seen by 2'), findsOneWidget);

      // A new next step: only Gus has seen it so far.
      server.readers = [_reader('Ugus00000001', 'Gus')];
      await session.reviseNextStep(_revisedStep);
      await tester.pumpAndSettle();

      expect(_textContaining(_revisedStep), findsOneWidget);
      expect(_text('Seen by 2'), findsNothing);
      expect(_text('Seen by 1'), findsOneWidget);
    });

    testWidgets('when the revised next step has no readers yet the old row '
        'goes away', (tester) async {
      final server = _Server()
        ..readers = [
          _reader('Ualice000001', 'Alice'),
          _reader('Ubob0000001', 'Bob'),
        ];
      final session = await _openRequestView(
        tester,
        viewer: author,
        server: server,
      );
      await _pumpNowSurface(tester, session.cubit);
      expect(_text('Seen by 2'), findsOneWidget);

      server.readers = [];
      await session.reviseNextStep(_revisedStep);
      await tester.pumpAndSettle();

      expect(_textContaining(_revisedStep), findsOneWidget);
      expect(_textContaining('Seen by'), findsNothing);
    });
  });

  testWidgets('on a 375x667 phone in Russian the "Seen by 2" row is shown in '
      'full, in Russian, and its list names both readers', (tester) async {
    await usePhoneSurface(tester);

    // The same Request without readers: everything on screen except the row.
    final bare = await _openRequestView(
      tester,
      viewer: author,
      server: _Server(),
    );
    await _pumpNowSurface(tester, bare.cubit, locale: const Locale('ru'));
    final withoutRow = _allText(tester);

    final session = await _openRequestView(
      tester,
      viewer: author,
      server: _Server()
        ..readers = [
          _reader('Ualice000001', 'Алиса Петрова'),
          _reader('Ubob0000001', 'Борис Сидоров'),
        ],
    );
    await _pumpNowSurface(tester, session.cubit, locale: const Locale('ru'));

    expect(_textContaining(_step), findsOneWidget);
    final rowText = _allText(tester).difference(withoutRow);
    expect(rowText, isNotEmpty, reason: 'readers add a row to the screen');
    expect(
      rowText.join(' '),
      contains('2'),
      reason: 'the row says how many people saw the update',
    );
    expect(
      rowText.join(' '),
      isNot(contains('Seen by')),
      reason: 'the row is in Russian',
    );
    expect(rowText.join(' '), matches('[А-Яа-яЁё]'));

    final row = find.byWidgetPredicate(
      (w) => w is RichText && rowText.contains(_plain(w)),
    );
    for (final element in row.evaluate()) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byWidget(element.widget),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      expect(paragraph.size.height, closeTo(painter.height, 0.5));
      painter.dispose();
    }
    expect(tester.takeException(), isNull);

    final countText = find.byWidgetPredicate(
      (w) =>
          w is RichText &&
          rowText.contains(_plain(w)) &&
          _plain(w).contains('2'),
    );
    await tester.tap(countText.first);
    await tester.pumpAndSettle();

    expect(_text('Алиса Петрова'), findsOneWidget);
    expect(_text('Борис Сидоров'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
