// Real HTTP/Ferry -> involvement mapper -> repository -> case -> cubit -> UI.
// Contract: batch rows carry beaconId; unreadable/missing ids are omitted and
// must remain unavailable, never inferred to be unseen.
// Required sibling matrix (each asserts involvement, block, lifecycle,
// unselectability, and a rendered localized subtitle in the readable test):
// 0: already sent; 1: helping; 2: recipient declined; 3: closed Request.
// 4: author-declined help offer is an ADDITIONAL case, not a replacement for 2.
// The harness also checks self-forward rejection before involvement reads.
// Browser gestures/focus/scroll require the web integration runner; these
// tests assert rendered content and state only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/person_forward_row.dart';
import 'package:tentura/features/forward/domain/use_case/person_forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/person_forward_screen.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

const _me = 'Uviewer000001';
const _dave = 'Udave00000001';
String _id(int i) => 'Bbatch${i.toString().padLeft(7, '0')}';

class _AuthoredBeacons implements BeaconRepository {
  _AuthoredBeacons(this.count, {this.includeAllCandidates = false});
  final int count;

  // Normal screen tests obey the fetched page limit. The overflow contract
  // is tested separately with a larger supplied candidate snapshot, without
  // requiring or claiming that today's screen fetches a second page.
  final bool includeAllCandidates;
  int? requestedLimit;

  @override
  Future<Iterable<Beacon>> fetchBeacons({
    required String profileId,
    required int offset,
    required List<int> lifecycleStates,
    int limit = 5,
  }) async {
    expect(profileId, _me);
    requestedLimit = limit;
    return [
      for (var i = 0; i < count && (includeAllCandidates || i < limit); i++)
        Beacon.empty.copyWith(
          id: _id(i),
          title: 'Request $i',
          author: const Profile(id: _me),
          status: i == 3 ? BeaconStatus.closed : BeaconStatus.open,
          updatedAt: DateTime.utc(2026, 10).subtract(Duration(minutes: i)),
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DaveProfiles implements ProfileRepositoryPort {
  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    if (ids.contains(_dave))
      const Profile(id: _dave, displayName: 'Dave', score: 1, rScore: 1),
  ];

  @override
  Stream<RepositoryEvent<Profile>> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _involvement(String id, {bool newlySent = false}) => {
  '__typename': 'v2_BeaconInvolvement',
  'beaconId': id,
  'forwardedToIds': [if (id == _id(0) || newlySent) _dave],
  'helpOfferedIds': [if (id == _id(1)) _dave],
  'withdrawnIds': <String>[],
  'declinedOfferIds': [if (id == _id(4)) _dave],
  'rejectedIds': [if (id == _id(2)) _dave],
  'watchingIds': <String>[],
  'onwardForwarderIds': <String>[],
  'myForwardedRecipients': [
    if (id == _id(0) || newlySent)
      {
        '__typename': 'v2_MyForwardRecipient',
        'edgeId': 'F$id',
        'recipientId': _dave,
        'note': '',
        'readAt': null,
        'hasOnwardChild': false,
        'recipientRejected': false,
      },
  ],
};

Map<String, dynamic> _answer(WireSent request, {String? newlySentId}) {
  final vars = request.variables;
  final ids = vars['ids'] as List?;
  return {
    '__typename': 'query_root',
    if (ids != null)
      'beaconInvolvements': [
        for (final id in ids.cast<String>().reversed)
          _involvement(id, newlySent: id == newlySentId),
      ]
    else
      'beaconInvolvement': _involvement(
        vars['id'] as String,
        newlySent: vars['id'] == newlySentId,
      ),
  };
}

Future<void> _withCubit(
  RemoteApiService remote,
  Future<void> Function(
    PersonForwardCubit cubit,
    TestRealtimeSyncPort realtime,
    _AuthoredBeacons beacons,
  )
  body, {
  int count = 11,
  int? expectedRowCount,
  bool includeAllCandidates = false,
  Future<void> Function(PersonForwardCubit cubit)? beforeLoaded,
}) async {
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final auth = StreamingAuthLocal(_me);
  final contactsRepo = FakeContactsRepository()
    ..fetchMineHandler = () async => {};
  final sync = buildTestRealtimeSync();
  final contacts = ContactsCase(
    contactsRepo,
    buildTestAuthCase(auth, EmptyAuthRemote()),
    store,
    sync.case_,
    env: const Env(),
    logger: Logger('PersonForwardBatchTest'),
  );
  final ready = contactsRepo.nextSync();
  auth.emit(_me);
  await ready;
  final beacons = _AuthoredBeacons(
    count,
    includeAllCandidates: includeAllCandidates,
  );
  final forwards = ForwardRepository(remote, beacons, sync.port);
  final case_ = PersonForwardCase(
    forwards,
    beacons,
    _DaveProfiles(),
    auth,
    contacts,
    env: const Env(),
    logger: Logger('PersonForwardBatchTest'),
  );
  PersonForwardCubit? cubit;
  try {
    await expectLater(case_.load(_me), throwsA(isA<StateError>()));
    expect(
      beacons.requestedLimit,
      isNull,
      reason: 'self-forward fails before loading Requests or involvement',
    );
    final loaded = PersonForwardCubit(
      personId: _dave,
      personForwardCase: case_,
      effects: FakeUiEffectPort(),
    );
    cubit = loaded;
    await Future.wait<void>([
      loaded.stream
          .firstWhere(
            (s) => s.rows.length == (expectedRowCount ?? count) && !s.isLoading,
          )
          .timeout(const Duration(seconds: 10))
          .then((_) {}),
      if (beforeLoaded != null) beforeLoaded(loaded),
    ]);
    await body(loaded, sync.port, beacons);
  } finally {
    await cubit?.close();
    await forwards.dispose();
    await contacts.dispose();
    await sync.port.dispose();
    await GetIt.I.unregister<ContactNameStore>();
    await store.dispose();
  }
}

Future<void> _pump(
  WidgetTester tester,
  PersonForwardCubit cubit,
  Locale locale,
) async {
  final screen = ScreenCubit(FakeUiEffectPort());
  addTearDown(screen.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PersonForwardCubit>.value(value: cubit),
            BlocProvider<ScreenCubit>.value(value: screen),
          ],
          child: Scaffold(
            body: BlocBuilder<PersonForwardCubit, PersonForwardState>(
              builder: (_, state) => personForwardBodyForTest(state: state),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _showRow(WidgetTester tester, int i) async {
  await tester.scrollUntilVisible(
    find.text('Request $i'),
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void _expectBatch(List<WireSent> sent, int count, {int attempts = 1}) {
  expect(
    sent,
    hasLength(attempts),
    reason:
        'one involvement operation for the screen, plus only the bounded retry',
  );
  for (final call in sent) {
    expect(
      call.variables['ids'],
      unorderedEquals([
        for (var i = 0; i < count; i++) _id(i),
      ]),
      reason: 'each batch must cover all authored Requests',
    );
  }
}

void _expectReadableMatrix(PersonForwardCubit cubit) {
  const matrix = [
    (
      0,
      'already sent',
      CandidateInvolvement.forwardedByMe,
      PersonForwardBlock.alreadySent,
      BeaconStatus.open,
    ),
    (
      1,
      'helping',
      CandidateInvolvement.helpOffered,
      PersonForwardBlock.alreadyHelping,
      BeaconStatus.open,
    ),
    (
      2,
      'recipient declined',
      CandidateInvolvement.declined,
      PersonForwardBlock.declined,
      BeaconStatus.open,
    ),
    (
      3,
      'closed Request',
      CandidateInvolvement.unseen,
      PersonForwardBlock.notOpen,
      BeaconStatus.closed,
    ),
    (
      4,
      'additional author-declined help offer',
      CandidateInvolvement.offerDeclinedByAuthor,
      PersonForwardBlock.declined,
      BeaconStatus.open,
    ),
  ];
  for (final (index, name, involvement, block, status) in matrix) {
    final row = cubit.state.rows.singleWhere((r) => r.beacon.id == _id(index));
    expect(row.involvement, involvement, reason: name);
    expect(row.block, block, reason: name);
    expect(row.beacon.status, status, reason: name);
    expect(row.isEligible, isFalse, reason: '$name must not be selectable');
    cubit.selectBeacon(row.beacon.id);
    expect(cubit.state.selectedBeaconId, isNull, reason: name);
  }
}

void _expectCappedChunks(List<WireSent> sent, int count) {
  final expectedSizes = switch (count) {
    50 => [50],
    51 => [50, 1],
    _ => throw ArgumentError.value(
      count,
      'count',
      'expected a boundary fixture',
    ),
  };
  expect(
    sent,
    hasLength(expectedSizes.length),
    reason:
        '$count candidates need ${expectedSizes.length} involvement batches',
  );
  final chunks = <List<String>>[];
  for (final call in sent) {
    expect(
      call.variables['ids'],
      isA<List<Object?>>(),
      reason: 'every involvement read must use the batch API',
    );
    final ids = (call.variables['ids'] as List).cast<String>();
    expect(ids, isNotEmpty);
    expect(
      ids.length,
      lessThanOrEqualTo(50),
      reason: 'the server rejects any operation exceeding 50 ids',
    );
    chunks.add(ids);
  }
  expect(chunks.map((ids) => ids.length), unorderedEquals(expectedSizes));
  expect(
    chunks.expand((ids) => ids),
    unorderedEquals([
      for (var i = 0; i < count; i++) _id(i),
    ]),
    reason: 'chunking must neither drop nor duplicate a Request',
  );
}

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    final phone = locale.languageCode == 'ru';
    group('Forward to person at ${phone ? '375x667 RU' : 'desktop EN'}', () {
      testWidgets(
        'one read preserves sent, helping, rejected, author-declined and closed rows',
        (tester) async {
          if (phone) {
            await usePhoneSurface(tester);
          } else {
            await tester.binding.setSurfaceSize(const Size(1440, 1000));
            addTearDown(() => tester.binding.setSurfaceSize(null));
          }
          final l10n = lookupL10n(locale);
          final sent = <WireSent>[];
          await tester.runAsync(
            () => withRemoteWire({}, sent, (remote) async {
              await _withCubit(remote, (cubit, _, beacons) async {
                expect(beacons.requestedLimit, 50);
                _expectReadableMatrix(cubit);
                expect(
                  cubit.state.rows.where((r) => r.isEligible),
                  hasLength(6),
                );
                await _pump(tester, cubit, locale);
                await _showRow(tester, 0);
                expect(
                  find.text(l10n.beaconForwardPersonReasonAlreadySent),
                  findsOneWidget,
                );
                expect(find.byTooltip(l10n.forwardEditAction), findsOneWidget);
                expect(
                  find.byTooltip(l10n.forwardCancelAction),
                  findsOneWidget,
                );
                final text = tester.renderObject<RenderParagraph>(
                  find.text(l10n.beaconForwardPersonReasonAlreadySent),
                );
                expect(text.didExceedMaxLines, isFalse);
                for (final (i, label) in [
                  (1, l10n.beaconForwardPersonReasonAlreadyHelping),
                  (2, l10n.beaconForwardPersonReasonDeclined),
                  (3, l10n.beaconForwardPersonReasonNotOpen),
                  (4, l10n.beaconForwardPersonReasonDeclined),
                ]) {
                  await _showRow(tester, i);
                  final tile = find
                      .ancestor(
                        of: find.text('Request $i'),
                        matching: find.byType(InkWell),
                      )
                      .first;
                  final subtitle = find.descendant(
                    of: tile,
                    matching: find.text(label),
                  );
                  expect(subtitle, findsOneWidget);
                  expect(
                    tester
                        .renderObject<RenderParagraph>(subtitle)
                        .didExceedMaxLines,
                    isFalse,
                  );
                }
                expect(tester.takeException(), isNull);
                await tester.pumpWidget(const SizedBox.shrink());
                _expectBatch(sent, 11);
              });
            }, responseFor: (request) async => _answer(request)),
          );
        },
      );

      testWidgets(
        'exhausted 1704 retries keep rows unavailable until the sender retries and recovers',
        (tester) async {
          if (phone) {
            await usePhoneSurface(tester);
          } else {
            await tester.binding.setSurfaceSize(const Size(1440, 1000));
            addTearDown(() => tester.binding.setSurfaceSize(null));
          }
          final l10n = lookupL10n(locale);
          final sent = <WireSent>[];
          final busy = {
            'message': 'Busy',
            'extensions': {'code': '1704', 'retryAfterMs': 1},
          };
          var failReads = true;
          final attemptsByRead = <String, int>{};
          final requestedIds = <String>{};
          final finalErrorsReturned = <String>{};
          final manualReads = <WireSent>[];
          late final Completer<void> finalAttemptsWaiting;
          late final Completer<void> releaseFinalErrors;
          await tester.runAsync(
            () => withRemoteWire(
              {},
              sent,
              (remote) async {
                // Create transport gates in runAsync's real timer zone.
                finalAttemptsWaiting = Completer<void>();
                releaseFinalErrors = Completer<void>();
                await _withCubit(
                  remote,
                  (cubit, _, _) async {
                    // The final automatic attempts were held at the transport.
                    // Loaded rows can be inspected only after every final error
                    // has returned and the cubit has consumed those responses.
                    expect(finalAttemptsWaiting.isCompleted, isTrue);
                    expect(
                      finalErrorsReturned,
                      unorderedEquals(attemptsByRead.keys),
                    );
                    expect(attemptsByRead, isNotEmpty);
                    expect(
                      attemptsByRead.values,
                      everyElement(3),
                      reason:
                          'each read must receive the initial 1704 and exhaust two automatic retries',
                    );
                    expect(cubit.state.isLoading, isFalse);
                    expect(cubit.state.rows, hasLength(11));
                    for (final row in cubit.state.rows) {
                      expect(row.isEligible, isFalse);
                      expect(
                        row.block,
                        PersonForwardBlock.involvementUnavailable,
                      );
                      cubit.selectBeacon(row.beacon.id);
                    }
                    expect(cubit.state.selectedBeaconId, isNull);
                    await _pump(tester, cubit, locale);
                    expect(
                      find.text(l10n.beaconForwardPersonReasonUnavailable),
                      findsWidgets,
                    );
                    expect(
                      find.text(l10n.beaconForwardPersonRetry),
                      findsWidgets,
                    );
                    for (final paragraph
                        in tester.renderObjectList<RenderParagraph>(
                          find.text(l10n.beaconForwardPersonReasonUnavailable),
                        )) {
                      expect(paragraph.didExceedMaxLines, isFalse);
                    }
                    expect(
                      find.byIcon(Icons.radio_button_unchecked),
                      findsNothing,
                    );
                    expect(tester.takeException(), isNull);
                    final failedAttempts = List<WireSent>.of(sent);
                    final exhaustedCounts = Map<String, int>.of(attemptsByRead);
                    // Keep the wire failing for longer than both remaining
                    // 1ms backoffs plus their maximum 100ms jitter. The settled
                    // screen must stay unavailable with no background retries.
                    await Future<void>.delayed(
                      const Duration(milliseconds: 300),
                    );
                    await tester.pumpAndSettle();
                    expect(attemptsByRead, exhaustedCounts);
                    expect(sent, failedAttempts);
                    expect(cubit.state.isLoading, isFalse);
                    expect(
                      cubit.state.rows.every(
                        (row) =>
                            !row.isEligible &&
                            row.block ==
                                PersonForwardBlock.involvementUnavailable,
                      ),
                      isTrue,
                    );
                    expect(
                      find.text(l10n.beaconForwardPersonReasonUnavailable),
                      findsWidgets,
                    );
                    expect(
                      find.text(l10n.beaconForwardPersonRetry),
                      findsWidgets,
                    );
                    expect(
                      find.byIcon(Icons.radio_button_unchecked),
                      findsNothing,
                    );
                    expect(cubit.state.selectedBeaconId, isNull);
                    // Only now may a new user-initiated load succeed.
                    expect(manualReads, isEmpty);
                    failReads = false;
                    final recovered = cubit.stream.firstWhere(
                      (s) => s.rows.any(
                        (r) => r.block == PersonForwardBlock.alreadySent,
                      ),
                    );
                    await tester.tap(
                      find.text(l10n.beaconForwardPersonRetry).first,
                    );
                    await recovered.timeout(const Duration(seconds: 10));
                    expect(
                      manualReads,
                      isNotEmpty,
                      reason:
                          'the Retry action must re-read the wire, not reuse failed data',
                    );
                    expect(
                      cubit.state.rows
                          .singleWhere((r) => r.beacon.id == _id(0))
                          .block,
                      PersonForwardBlock.alreadySent,
                    );
                    expect(
                      cubit.state.rows
                          .singleWhere((r) => r.beacon.id == _id(5))
                          .isEligible,
                      isTrue,
                    );
                    expect(
                      cubit.state.rows.where((r) => r.isEligible),
                      hasLength(6),
                    );
                    await tester.pumpAndSettle();
                    expect(
                      find.text(l10n.beaconForwardPersonReasonUnavailable),
                      findsNothing,
                    );
                    await tester.pumpWidget(const SizedBox.shrink());
                    _expectBatch(failedAttempts, 11, attempts: 3);
                    _expectBatch(sent.skip(failedAttempts.length).toList(), 11);
                  },
                  beforeLoaded: (loadingCubit) async {
                    try {
                      await finalAttemptsWaiting.future.timeout(
                        const Duration(seconds: 10),
                      );
                      expect(attemptsByRead.values, everyElement(3));
                      expect(
                        finalErrorsReturned,
                        isEmpty,
                        reason:
                            'terminal retry responses are still held by the wire',
                      );
                      expect(
                        loadingCubit.state.isLoading,
                        isTrue,
                        reason:
                            'automatic retries must finish before publishing rows',
                      );
                      expect(loadingCubit.state.rows, isEmpty);
                    } finally {
                      releaseFinalErrors.complete();
                    }
                  },
                );
              },
              errorFor: (request) async {
                if (!failReads) {
                  manualReads.add(request);
                  return null;
                }
                final key = jsonEncode(request.variables);
                final attempt = attemptsByRead.update(
                  key,
                  (n) => n + 1,
                  ifAbsent: () => 1,
                );
                requestedIds.addAll(
                  request.variables['ids'] is List
                      ? (request.variables['ids'] as List).cast<String>()
                      : [request.variables['id'] as String],
                );
                if (requestedIds.length == 11 &&
                    attemptsByRead.values.every((n) => n == 3) &&
                    !finalAttemptsWaiting.isCompleted) {
                  finalAttemptsWaiting.complete();
                }
                if (attempt == 3) {
                  await releaseFinalErrors.future;
                  finalErrorsReturned.add(key);
                }
                return busy;
              },
              responseFor: (request) async => _answer(request),
            ),
          );
        },
      );
    });
  }

  test(
    'fifty authored Requests use one capped involvement operation',
    () async {
      final sent = <WireSent>[];
      await withRemoteWire({}, sent, (remote) async {
        await _withCubit(remote, (cubit, _, beacons) async {
          expect(beacons.requestedLimit, 50);
          expect(cubit.state.rows, hasLength(50));
          expect(
            cubit.state.rows.firstWhere((r) => r.beacon.id == _id(0)).block,
            PersonForwardBlock.alreadySent,
          );
          _expectCappedChunks(sent, 50);
          _expectBatch(sent, 50);
        }, count: 50);
      }, responseFor: (request) async => _answer(request));
    },
  );

  test(
    'fifty one authored Requests keep the first screen page within fifty ids',
    () async {
      final sent = <WireSent>[];
      await withRemoteWire({}, sent, (remote) async {
        await _withCubit(
          remote,
          (cubit, _, beacons) async {
            expect(beacons.count, 51);
            expect(beacons.requestedLimit, 50);
            expect(cubit.state.rows, hasLength(50));
            expect(
              cubit.state.rows.map((r) => r.beacon.id),
              isNot(contains(_id(50))),
              reason: 'paging remains capped at 50',
            );
            _expectCappedChunks(sent, 50);
          },
          count: 51,
          expectedRowCount: 50,
        );
      }, responseFor: (request) async => _answer(request));
    },
  );

  test(
    'fifty one supplied candidates are read in batches of fifty and one',
    () async {
      final sent = <WireSent>[];
      await withRemoteWire({}, sent, (remote) async {
        await _withCubit(
          remote,
          (cubit, _, _) async {
            expect(cubit.state.rows, hasLength(51));
            _expectReadableMatrix(cubit);
            final overflow = cubit.state.rows.singleWhere(
              (r) => r.beacon.id == _id(50),
            );
            expect(overflow.involvement, CandidateInvolvement.unseen);
            expect(overflow.isEligible, isTrue);
            cubit.selectBeacon(overflow.beacon.id);
            expect(cubit.state.selectedBeaconId, _id(50));
            _expectCappedChunks(sent, 51);
          },
          count: 51,
          includeAllCandidates: true,
        );
      }, responseFor: (request) async => _answer(request));
    },
  );

  test(
    'a realtime forward hint refreshes all rows with one involvement operation',
    () async {
      final sent = <WireSent>[];
      String? newlySentId;
      await withRemoteWire(
        {},
        sent,
        (remote) async {
          await _withCubit(remote, (cubit, realtime, _) async {
            cubit.selectBeacon(_id(5));
            expect(cubit.state.selectedBeaconId, _id(5));
            sent.clear();
            newlySentId = _id(5);
            final refreshed = cubit.stream.firstWhere(
              (s) => s.rows.any(
                (r) =>
                    r.beacon.id == _id(5) &&
                    r.block == PersonForwardBlock.alreadySent,
              ),
            );
            realtime.emitChange(
              RealtimeEntityChange(
                kind: RealtimeEntityKind.forward,
                aggregateId: _id(5),
                operation: RealtimeOperation.insert,
                source: RealtimeChangeSource.serverInvalidation,
              ),
            );
            await refreshed.timeout(const Duration(seconds: 10));
            expect(cubit.state.selectedBeaconId, isNull);
            _expectBatch(sent, 11);
          });
        },
        responseFor: (request) async =>
            _answer(request, newlySentId: newlySentId),
      );
    },
  );
}
