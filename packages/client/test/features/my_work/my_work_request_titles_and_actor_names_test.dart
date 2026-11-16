// My Work and the Request Timeline name the Request and the person.
//
// Real path: the GraphQL response as the server sends it → Ferry →
// AttentionRepository → AttentionCase → MyWorkCubit → the My Work card row.
// Only HTTP is faked. The Timeline sheet is fed receipts through the same
// AttentionCase and resolves the actor through AttentionActorProfilesCase.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/attention/ui/widget/request_attention_timeline_sheet.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'my_work_test_support.dart';

const _viewerId = 'Uviewer000001';
const _annaId = 'Uanna000000001';
const _beaconId = 'Be80948436804';
const _requestTitle = 'Fix the roof';

/// The card's own header title differs from the title the receipt carries, so
/// a row can only show [_requestTitle] by reading the receipt's `beaconTitle`.
const _cardTitle = 'Garden shed';

final _beacon = Beacon.empty.copyWith(
  id: _beaconId,
  title: _cardTitle,
  status: BeaconStatus.open,
  author: const Profile(id: _viewerId, displayName: 'Me'),
);

Map<String, dynamic> _wireReceipt({
  String id = 'Nrow00000000001',
  String presentationKey = 'deadline_changed',
  bool requiresAction = false,
  String? actorUserId = _annaId,
  Map<String, Object?> payload = const {},
  Object? beaconTitle = _requestTitle,
  Object? beaconKind = 0,
  Object? postRootExcerpt,
}) => {
  '__typename': 'v2_AttentionReceipt',
  'id': id,
  'category': requiresAction ? 'coordination' : 'requestProgress',
  'kind': requiresAction ? 'needsMe' : 'roomActivityLowPriority',
  'priority': 'normal',
  'title': 'Generic server title',
  'body': '',
  'actionUrl': '/#/beacon/view/$_beaconId',
  'createdAt': '2026-11-11T12:00:00Z',
  'collapsedCount': 1,
  'beaconId': _beaconId,
  'actorUserId': actorUserId,
  'presentationKey': presentationKey,
  'presentationPayloadJson': jsonEncode({
    'eventType': presentationKey,
    'beaconId': _beaconId,
    ..._deadlinePayload,
    ...payload,
  }),
  'requiresAction': requiresAction,
  'surface': 'myWork',
  'itemKind': 'receipt',
  'beaconTitle': beaconTitle,
  'beaconKind': beaconKind,
  'postRootExcerpt': postRootExcerpt,
};

Map<String, dynamic> _myWorkResponse({
  Map<String, dynamic>? latestUnseen,
  List<Map<String, dynamic>> liveObligations = const [],
}) => {
  '__typename': 'query_root',
  'myWorkAttention': [
    {
      '__typename': 'v2_MyWorkBeaconAttention',
      'beaconId': _beaconId,
      'unseenCount': 1,
      'needsYouAt': null,
      'firstEntryAt': null,
      'latestUnseen': latestUnseen,
      'liveObligations': liveObligations,
    },
  ],
};

/// What makes the U10 copy for `deadline_changed` name the person.
const _deadlinePayload = {'newEndAt': '2026-11-21T18:00:00.000'};

final class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

/// Resolves Anna only; every other id is unknown.
final class _Profiles extends Mock implements ProfileRepositoryPort {
  _Profiles({this.annaName = 'Anna'});

  final String annaName;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    if (ids.contains(_annaId)) Profile(id: _annaId, displayName: annaName),
  ];

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> update(
    Profile profile, {
    String? displayName,
    String? description,
    bool dropImage = false,
    ImageEntity? image,
    bool updateHandle = false,
    String? handle,
  }) => throw UnimplementedError();
}

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _viewerId, displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

Future<MyWorkCubit> _cubit(RemoteRequestClient remote) async {
  final attention = AttentionCase(
    AttentionRepository(remote),
    _Accounts(),
    buildTestRealtimeSync().case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-work-names'),
  );
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: const <Beacon>[],
      helpOfferedNonArchived: [
        (
          beacon: _beacon,
          offerHelpMessage: 'I can sew',
          helpType: null,
          authorResponseType: CoordinationResponseType.useful,
          stakeState: CommitmentStakeState.acknowledged,
          forwarderSenders: const <Profile>[],
          helpOfferRowUpdatedAt: DateTime(2026, 9, 4),
          authorCoordinationUpdatedAt: DateTime(2026, 9, 5),
          coordinationAuthor: null,
        ),
      ],
      obligationBeacons: [(beacon: _beacon, viewerArchived: false)],
      archivedCountHint: 0,
    );
  final cubit = MyWorkCubit(
    userId: _viewerId,
    myWorkCase: buildTestMyWorkCase(repo: repo, attentionCase: attention),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.isSuccess && s.attentionLoaded);
  return cubit;
}

Future<void> _pumpDesk(
  WidgetTester tester,
  MyWorkCubit cubit, {
  Locale locale = const Locale('en'),
}) async {
  tester.view
    ..physicalSize = const Size(400, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<MyWorkCubit>.value(value: cubit),
            BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          ],
          child: Scaffold(
            body: BlocBuilder<MyWorkCubit, MyWorkState>(
              builder: (context, state) => ListView(
                children: [
                  for (final vm in state.nonArchivedCards)
                    MyWorkCardRouter(vm: vm),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Actor profiles resolve asynchronously; real time passes inside runAsync.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

/// All text (plain and rich) under [row], in tree order.
String _textUnder(Finder row) => find
    .descendant(of: row, matching: find.byType(Text))
    .evaluate()
    .map((e) {
      final t = e.widget as Text;
      return t.data ?? t.textSpan?.toPlainText() ?? '';
    })
    .join('\n');

/// All text inside the attention row of receipt [id] (rows are keyed by id).
String _rowText(WidgetTester tester, String id) {
  final row = find.byKey(ValueKey(id));
  expect(row, findsOneWidget, reason: 'the My Work row for $id is on screen');
  return _textUnder(row);
}

Future<void> _withDesk(
  WidgetTester tester,
  Map<String, dynamic> response,
  Future<void> Function(MyWorkCubit cubit) body, {
  Locale locale = const Locale('en'),
}) async {
  GetIt.I.registerSingleton<AttentionActorProfilesCase>(
    AttentionActorProfilesCase(_Profiles(), _Accounts()),
  );
  await tester.runAsync(
    () => withRemoteWire(
      {},
      [],
      (remote) async {
        final cubit = await _cubit(remote);
        await _pumpDesk(tester, cubit, locale: locale);
        await body(cubit);
      },
      responseFor: (request) async => switch (request.operationName) {
        'MyWorkAttention' => response,
        'AttentionLiveObligations' => {
          'liveObligationBeacons': <String>[_beaconId],
        },
        'AttentionMarkers' => {
          'attentionMarkers': {'unreadBeaconIds': <String>[]},
        },
        _ => {},
      },
    ),
  );
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-names'));
    }
  });

  tearDown(GetIt.I.reset);

  group('my work attention query', () {
    for (final field in ['latestUnseen', 'liveObligations']) {
      test('the query document requests the Request identity on $field', () {
        final doc =
            File(
                  'lib/features/attention/data/gql/my_work_attention.graphql',
                )
                .readAsStringSync()
                .split('\n')
                .map((l) => l.split('#').first)
                .join('\n');
        final start = RegExp('\\b$field\\s*\\{').firstMatch(doc);
        expect(start, isNotNull, reason: '$field selection is in the query');
        // Brace-balanced: fields selected directly under [field] (depth 1).
        var depth = 0;
        final top = StringBuffer();
        for (var i = start!.end - 1; i < doc.length; i++) {
          final c = doc[i];
          if (c == '{') {
            depth++;
          } else if (c == '}') {
            depth--;
            if (depth == 0) break;
          } else if (depth == 1) {
            top.write(c);
          }
        }
        final selected = top.toString().split(RegExp(r'[\s,]+')).toSet();
        expect(
          selected,
          containsAll(['beaconTitle', 'beaconKind', 'postRootExcerpt']),
        );
      });
    }

    test('maps the Request title and kind onto latestUnseen and every '
        'live obligation', () async {
      await withRemoteWire(
        {},
        [],
        (remote) async {
          final rows = await AttentionRepository(
            remote,
          ).myWorkAttention({_beaconId});
          final row = rows.single;
          expect(row.latestUnseen?.beaconTitle, _requestTitle);
          expect(row.latestUnseen?.beaconKind, 0);
          expect(row.liveObligations, hasLength(2));
          for (final obligation in row.liveObligations) {
            expect(obligation.beaconTitle, _requestTitle);
            expect(obligation.beaconKind, 0);
          }
        },
        responseFor: (_) async => _myWorkResponse(
          latestUnseen: _wireReceipt(id: 'Nlatest0000001'),
          liveObligations: [
            _wireReceipt(
              id: 'Nobl0000000001',
              requiresAction: true,
              presentationKey: 'offer_declined',
            ),
            _wireReceipt(
              id: 'Nobl0000000002',
              requiresAction: true,
              presentationKey: 'offer_declined',
            ),
          ],
        ),
      );
    });

    test('maps a Post root excerpt', () async {
      await withRemoteWire(
        {},
        [],
        (remote) async {
          final row = (await AttentionRepository(
            remote,
          ).myWorkAttention({_beaconId})).single;
          expect(row.latestUnseen?.beaconKind, 1);
          expect(row.latestUnseen?.postRootExcerpt, 'Need a ladder');
        },
        responseFor: (_) async => _myWorkResponse(
          latestUnseen: _wireReceipt(
            beaconKind: 1,
            postRootExcerpt: 'Need a ladder',
          ),
        ),
      );
    });
  });

  group('my work card rows', () {
    testWidgets('an update from someone who is not a helper shows that '
        "person's name in its row", (tester) async {
      await _withDesk(
        tester,
        _myWorkResponse(latestUnseen: _wireReceipt()),
        (_) async {
          final text = _rowText(tester, 'Nrow00000000001');
          expect(text, contains('Anna'));
          expect(text, contains(_requestTitle));
        },
      );
    });

    testWidgets('an obligation row reads the named headline, not the '
        'generic one', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final named = resolveUpdatesFeedRowCopy(
        title: 'Generic server title',
        body: '',
        presentationKey: 'offer_declined',
        presentationPayloadJson: jsonEncode({'eventType': 'offer_declined'}),
        l10n: l10n,
        actorName: 'Anna',
      ).headline;
      expect(named, contains('Anna'), reason: 'fixture: U10 copy names Anna');

      await _withDesk(
        tester,
        _myWorkResponse(
          liveObligations: [
            _wireReceipt(
              id: 'Nobl0000000001',
              requiresAction: true,
              presentationKey: 'offer_declined',
            ),
          ],
        ),
        (_) async {
          final text = _rowText(tester, 'Nobl0000000001');
          expect(text, contains(named));
          expect(text, isNot(contains(l10n.updatesFallbackTitleOfferDeclined)));
        },
      );
    });

    testWidgets('a Post row carries the Post label with its opening words', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final expected = resolveUpdatesFeedRowCopy(
        title: 'Generic server title',
        body: '',
        presentationKey: 'post_first_response',
        presentationPayloadJson: jsonEncode({
          'eventType': 'post_first_response',
        }),
        l10n: l10n,
        actorName: 'Anna',
        isPost: true,
        postRootExcerpt: 'Need a ladder',
      );
      final label = expected.body;
      expect(label, contains('Need a ladder'));

      await _withDesk(
        tester,
        _myWorkResponse(
          latestUnseen: _wireReceipt(
            presentationKey: 'post_first_response',
            beaconKind: 1,
            postRootExcerpt: 'Need a ladder',
          ),
        ),
        (_) async {
          expect(_rowText(tester, 'Nrow00000000001'), contains(label));
        },
      );
    });

    testWidgets('a receipt whose Request title is unreadable shows no '
        'null and no empty quotes', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final headline = resolveUpdatesFeedRowCopy(
        title: 'Generic server title',
        body: '',
        presentationKey: 'deadline_changed',
        presentationPayloadJson: jsonEncode({
          'eventType': 'deadline_changed',
          ..._deadlinePayload,
        }),
        l10n: l10n,
        actorName: 'Anna',
      ).headline;
      expect(headline, contains('Anna'));
      await _withDesk(
        tester,
        _myWorkResponse(latestUnseen: _wireReceipt(beaconTitle: null)),
        (_) async {
          final text = _rowText(tester, 'Nrow00000000001');
          expect(text, contains(headline));
          expect(text, isNot(contains(_requestTitle)));
          expect(text, isNot(contains(_cardTitle)));
          expect(text, isNot(contains('null')));
          expect(text, isNot(contains('«»')));
          expect(text, contains('Anna'));
        },
      );
    });
  });

  group('request timeline sheet', () {
    late _TimelineRepository repository;
    late AttentionCase attention;
    late TestRealtimeSyncPort realtimePort;

    Future<void> pumpSheet(
      WidgetTester tester, {
      required Locale locale,
      required String annaName,
      String? actorUserId = _annaId,
    }) async {
      repository = _TimelineRepository()
        ..page = AttentionFeedPage(
          items: [
            AttentionReceipt(
              id: 'Ntl000000000001',
              category: 'requestProgress',
              kind: 'roomActivityLowPriority',
              priority: 'normal',
              title: 'Generic server title',
              body: '',
              actionUrl: '/#/',
              createdAt: DateTime.utc(2026, 11, 11),
              collapsedCount: 1,
              presentationKey: 'request_status_changed',
              presentationPayloadJson: jsonEncode({
                'eventType': 'requestStatusChanged',
                'toStatus': 'closed',
              }),
              beaconId: _beaconId,
              actorUserId: actorUserId,
              surface: AttentionSurface.activity,
            ),
          ],
        );
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      attention = AttentionCase(
        repository,
        _Accounts(),
        realtime.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('timeline-names'),
      );
      GetIt.I
        ..registerSingleton<AttentionCase>(attention)
        ..registerSingleton<AttentionActorProfilesCase>(
          AttentionActorProfilesCase(
            _Profiles(annaName: annaName),
            _Accounts(),
          ),
        );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 800)),
          child: TenturaResponsiveScope(
            child: MaterialApp(
              locale: locale,
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: const Scaffold(
                body: RequestAttentionTimelineSheet(beaconId: _beaconId),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder row() => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.identifier == TestIds.updatesReceipt('Ntl000000000001'),
    );

    String rowText(WidgetTester tester) {
      expect(row(), findsOneWidget);
      return _textUnder(row());
    }

    tearDown(() async {
      await attention.dispose();
      await realtimePort.dispose();
    });

    testWidgets('names the person in the headline (EN)', (tester) async {
      await pumpSheet(tester, locale: const Locale('en'), annaName: 'Anna');
      expect(rowText(tester), contains('Anna'));
    });

    testWidgets('names the person in the Russian copy, not the English '
        'one (RU)', (tester) async {
      await pumpSheet(tester, locale: const Locale('ru'), annaName: 'Anna');
      final en = await L10n.delegate.load(const Locale('en'));
      final ru = await L10n.delegate.load(const Locale('ru'));
      final expected = resolveUpdatesFeedRowCopy(
        title: 'Generic server title',
        body: '',
        presentationKey: 'request_status_changed',
        presentationPayloadJson: jsonEncode({
          'eventType': 'requestStatusChanged',
          'toStatus': 'closed',
        }),
        l10n: ru,
        actorName: 'Anna',
      ).headline;
      final english = resolveUpdatesFeedRowCopy(
        title: 'Generic server title',
        body: '',
        presentationKey: 'request_status_changed',
        presentationPayloadJson: jsonEncode({
          'eventType': 'requestStatusChanged',
          'toStatus': 'closed',
        }),
        l10n: en,
        actorName: 'Anna',
      ).headline;
      expect(expected, contains('Anna'));
      expect(expected, isNot(english));
      final text = rowText(tester);
      expect(text, contains(expected));
      expect(text, isNot(contains(english)));
    });

    for (final (label, name, actor) in [
      ('has no profile', 'Anna', 'Unobody000001'),
      ('has an empty display name', '', _annaId),
    ]) {
      testWidgets('shows the nameless headline when the actor $label', (
        tester,
      ) async {
        await pumpSheet(
          tester,
          locale: const Locale('en'),
          annaName: name,
          actorUserId: actor,
        );
        final en = await L10n.delegate.load(const Locale('en'));
        final nameless = resolveUpdatesFeedRowCopy(
          title: 'Generic server title',
          body: '',
          presentationKey: 'request_status_changed',
          presentationPayloadJson: jsonEncode({
            'eventType': 'requestStatusChanged',
            'toStatus': 'closed',
          }),
          l10n: en,
        ).headline;
        final text = rowText(tester);
        expect(
          find.descendant(
            of: row(),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Text &&
                  (w.data ?? w.textSpan?.toPlainText()) == nameless,
            ),
          ),
          findsOneWidget,
          reason: 'the headline is exactly the nameless copy: $text',
        );
        expect(text, isNot(contains('null')));
        expect(text, isNot(contains('Anna')));
        for (final line in text.split('\n')) {
          expect(line.startsWith(' · '), isFalse, reason: line);
          expect(line.startsWith(': '), isFalse, reason: line);
          expect(line.trimLeft().startsWith('·'), isFalse, reason: line);
        }
      });
    }
  });
}

final class _TimelineRepository extends AttentionRepositoryFake {
  AttentionFeedPage page = const AttentionFeedPage();
  int historyCalls = 0;

  @override
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async {
    historyCalls++;
    return page;
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => throw UnimplementedError();

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}
