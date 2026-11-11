import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/features/forward/ui/widget/forward_band_strip.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker_entry.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/forward/ui/widget/forward_tag_picker.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';

const _beaconId = 'Bscroll000001';
String _id(int index) => 'U${index.toString().padLeft(11, '0')}';

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();
  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

class _Beacons extends Fake implements BeaconRepository {
  @override
  Future<Beacon> fetchBeaconById(String id) async =>
      Beacon.empty.copyWith(id: id, title: 'Помощь');
}

class _FactCards extends Fake implements BeaconFactCardRepository {}

class _Profiles extends Fake implements ProfileRepositoryPort {}

class _Capabilities extends Fake implements CapabilityRepositoryPort {
  _Capabilities(this.showBand);
  final bool showBand;

  @override
  Future<Map<String, List<String>>> fetchTopCapabilitiesBatch({
    required List<String> subjectIds,
    int limit = 2,
    List<String> prioritizeSlugs = const [],
  }) async => {};

  @override
  Future<List<ForwardBandRow>> fetchForwardContext({
    required String beaconId,
    String? context,
  }) async => [
    if (showBand)
      for (var i = 90; i < 95; i++)
        ForwardBandRow(userId: _id(i), isExploration: true),
  ];
}

Map<String, dynamic> _wireCandidate(int i) => {
  '__typename': 'v2_user',
  'id': _id(i),
  'displayName': 'Человек ${i.toString().padLeft(3, '0')}',
  'handle': null,
  'description': '',
  'my_vote': i < 100 ? 1 : 0,
  'trusts_viewer': i < 100,
  'is_mutual_friend': i < 100,
  'shares_active_context': false,
  'image': null,
  'scores': [
    {'src_score': 1.0, 'dst_score': (300 - i).toDouble()},
  ],
  'user_presence': null,
  'user_availability': null,
  'forward_reach': {
    'kind': i < 100
        ? 'direct'
        : i < 200
        ? 'via_connection'
        : 'wider',
    'via_count': i >= 100 && i < 200 ? 1 : 0,
    'via': [
      if (i >= 100 && i < 200)
        {'id': 'Uconnection01', 'displayName': 'Связь', 'image': null},
    ],
    'shared_request_id': null,
    'shared_request_title': null,
  },
};

/// Only HTTP is replaced for candidates: real Ferry deserialization, mapper,
/// repository, use case and cubit feed the same picker used by both hosts.
Future<void> _withPicker(
  WidgetTester tester, {
  required bool selectedWithBand,
  required Future<void> Function(ForwardCubit cubit, Map<String, int> builds)
  check,
}) async {
  await usePhoneSurface(tester);
  tester.view
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.runAsync(() async {
    final store = ContactNameStore();
    final auth = StreamingAuthLocal();
    final realtime = buildTestRealtimeSync();
    final contactsRepo = FakeContactsRepository()
      ..fetchMineHandler = () async => {};
    final contacts = ContactsCase(
      contactsRepo,
      buildTestAuthCase(auth, EmptyAuthRemote()),
      store,
      realtime.case_,
      env: const Env(),
      logger: Logger('ForwardScrollBudget'),
    );
    GetIt.I.registerSingleton<ContactNameStore>(store);
    GetIt.I.registerSingleton<CapabilityRepositoryPort>(
      _Capabilities(selectedWithBand),
    );
    final synced = contactsRepo.nextSync();
    auth.emit('Uviewer000001');
    await synced.timeout(const Duration(seconds: 10));
    final sent = <WireSent>[];
    try {
      await withRemoteWire(
        {
          'ForwardCandidatesFetch': {
            '__typename': 'query_root',
            'forwardCandidates': [
              for (var i = 0; i < 300; i++) _wireCandidate(i),
            ],
          },
          'BeaconInvolvementData': {
            '__typename': 'query_root',
            'beaconInvolvement': {
              '__typename': 'v2_BeaconInvolvement',
              'beaconId': _beaconId,
              'forwardedToIds': <String>[],
              'helpOfferedIds': <String>[],
              'withdrawnIds': <String>[],
              'rejectedIds': <String>[],
              'watchingIds': <String>[],
              'onwardForwarderIds': <String>[],
              'declinedOfferIds': <String>[],
              'myForwardedRecipients': <Object>[],
            },
          },
        },
        sent,
        (remote) async {
          final repository = ForwardRepository(
            remote,
            _Beacons(),
            realtime.port,
          );
          final cubit = ForwardCubit(
            beaconId: _beaconId,
            embedded: true,
            initialSelectedIds: {
              if (selectedWithBand)
                for (var i = 0; i < 5; i++) _id(i),
            },
            forwardCase: ForwardCase(
              repository,
              auth,
              _FactCards(),
              _Profiles(),
              contacts,
              noopBlockCase(),
              env: const Env(),
              logger: Logger('ForwardScrollBudget'),
            ),
            effects: FakeUiEffectPort(),
          );
          try {
            await cubit.stream
                .firstWhere(
                  (s) =>
                      s.candidatesLoad is ForwardCandidatesReady ||
                      s.candidatesLoad is ForwardCandidatesError,
                )
                .timeout(const Duration(seconds: 10));
            expect(cubit.state.candidatesLoad, isA<ForwardCandidatesReady>());
            expect(cubit.state.candidates, hasLength(300));
            expect(
              sent.map((r) => r.operationName),
              contains('ForwardCandidatesFetch'),
            );
            final builds = <String, int>{};
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('ru'),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                theme: TenturaTheme.light(),
                home: TenturaResponsiveScope(
                  child: MultiBlocProvider(
                    providers: [
                      BlocProvider<ForwardCubit>.value(value: cubit),
                      BlocProvider<ProfileCubit>.value(value: _ProfileCubit()),
                    ],
                    child: Scaffold(
                      body: ForwardRecipientPicker(
                        beaconId: _beaconId,
                        embedded: true,
                        debugOnRowBuild: (id) =>
                            builds[id] = (builds[id] ?? 0) + 1,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final picker = find.byType(ForwardRecipientPicker);
            final pickerContext = tester.element(picker);
            expect(MediaQuery.sizeOf(pickerContext), const Size(375, 667));
            expect(tester.getSize(picker), const Size(375, 667));
            expect(Localizations.localeOf(pickerContext), const Locale('ru'));
            await check(cubit, builds);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await cubit.close();
            await repository.dispose();
          }
        },
      );
    } finally {
      await contacts.dispose();
      await realtime.port.dispose();
      await auth.dispose();
      await GetIt.I.unregister<CapabilityRepositoryPort>();
      await GetIt.I.unregister<ContactNameStore>();
      await store.dispose();
    }
  });
}

Map<String, Element> _mountedEntries() => {
  for (final element
      in find
          .byType(ForwardRecipientPickerEntry, skipOffstage: false)
          .evaluate())
    (element.widget as ForwardRecipientPickerEntry).candidate.id: element,
};

List<String> _compositingViolations(Finder entry, String state) {
  expect(entry, findsOneWidget);
  return [
    for (final type in [
      Opacity,
      ClipPath,
      ShaderMask,
      BackdropFilter,
      ColorFiltered,
    ])
      if (find
          .descendant(of: entry, matching: find.byType(type))
          .evaluate()
          .isNotEmpty)
        '$state entry contains $type',
  ];
}

void main() {
  testWidgets(
    'recipient entries avoid compositing widgets before and after selecting and opening a note',
    (tester) async {
      await _withPicker(
        tester,
        selectedWithBand: false,
        check: (cubit, _) async {
          final id = _id(0);
          final entry = find.byWidgetPredicate(
            (w) => w is ForwardRecipientPickerEntry && w.candidate.id == id,
          );
          expect(cubit.state.selectedIds, isEmpty);
          final violations = _compositingViolations(entry, 'unselected');
          await tester.tap(
            find.byKey(TestIds.key(TestIds.forwardRecipientCheckbox(id))),
          );
          await tester.pumpAndSettle();
          expect(cubit.state.selectedIds, contains(id));
          violations.addAll(_compositingViolations(entry, 'selected'));
          await tester.tap(
            find.descendant(
              of: entry,
              matching: find.byIcon(Icons.add_comment_outlined),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: entry, matching: find.byType(TextField)),
            findsOneWidget,
          );
          violations.addAll(_compositingViolations(entry, 'note open'));
          expect(tester.takeException(), isNull);
          expect(violations, isEmpty);
        },
      );
    },
  );
  testWidgets(
    '375x667 RU picker reaches and selects its final recipient without rebuilding neighbors',
    (tester) async {
      await _withPicker(
        tester,
        selectedWithBand: false,
        check: (cubit, builds) async {
          final picker = find.byType(ForwardRecipientPicker);
          final context = tester.element(picker);
          expect(MediaQuery.sizeOf(context), const Size(375, 667));
          expect(tester.getSize(picker), const Size(375, 667));
          expect(Localizations.localeOf(context), const Locale('ru'));
          expect(cubit.state.candidates, hasLength(300));
          final lastId = cubit.state.candidates.last.id;
          final last = find.byKey(
            TestIds.key(TestIds.forwardRecipient(lastId)),
          );
          expect(
            last,
            findsNothing,
            reason: 'the final recipient starts off screen',
          );
          final scrollable = find
              .descendant(of: picker, matching: find.byType(Scrollable))
              .first;
          final expander = find.byKey(ForwardRecipientPicker.widerExpanderKey);
          await tester.scrollUntilVisible(
            expander,
            400,
            maxScrolls: 350,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          await tester.tap(expander);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            last,
            400,
            maxScrolls: 350,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          expect(last.hitTestable(), findsOneWidget);
          final checkbox = find.byKey(
            TestIds.key(TestIds.forwardRecipientCheckbox(lastId)),
          );
          expect(checkbox.hitTestable(), findsOneWidget);
          expect(cubit.state.selectedIds, isNot(contains(lastId)));
          final beforeSelect = Map<String, int>.from(builds);
          await tester.tap(checkbox);
          await tester.pumpAndSettle();
          expect(cubit.state.selectedIds, contains(lastId));
          expect(last.hitTestable(), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason:
                'the full RU phone journey must have no overflow or other exception',
          );
          expect(
            builds.keys.where((id) => builds[id] != beforeSelect[id]),
            [lastId],
            reason:
                'selecting the last recipient must preserve neighboring rows',
          );
        },
      );
    },
  );
  for (final selectedWithBand in [false, true]) {
    testWidgets(
      '300 recipients keep scroll builds bounded and selection local '
      '${selectedWithBand ? 'with five selected and a contextual band' : 'without selection'}',
      (tester) async {
        await _withPicker(
          tester,
          selectedWithBand: selectedWithBand,
          check: (cubit, builds) async {
            final failures = <String>[];
            final initialCount = builds.length;
            if (initialCount > 50) {
              failures.add(
                'first settled frame built $initialCount distinct rows (limit 50)',
              );
            }
            expect(tester.takeException(), isNull);
            expect(
              find.byType(ForwardTagPicker, skipOffstage: false),
              findsOneWidget,
            );
            if (selectedWithBand) {
              expect(cubit.state.selectedIds, hasLength(5));
              for (final id in cubit.state.selectedIds) {
                final entry = find.byWidgetPredicate(
                  (widget) =>
                      widget is ForwardRecipientPickerEntry &&
                      widget.candidate.id == id,
                  skipOffstage: false,
                );
                expect(
                  entry,
                  findsOneWidget,
                  reason:
                      'each selected recipient must be mounted before the measured drag',
                );
                expect(
                  find.descendant(
                    of: entry,
                    matching: find.byIcon(
                      Icons.add_comment_outlined,
                      skipOffstage: false,
                    ),
                  ),
                  findsOneWidget,
                  reason:
                      'selected recipient $id must expose its + Note control before scrolling',
                );
                final row = tester.widget<ForwardRecipientRow>(
                  find.descendant(
                    of: entry,
                    matching: find.byType(
                      ForwardRecipientRow,
                      skipOffstage: false,
                    ),
                  ),
                );
                expect(row.isSelected, isTrue);
                expect(row.showsPersonalNoteSlot, isTrue);
                expect(row.onOpenPersonalNote, isNotNull);
              }
              expect(find.byType(ForwardBandStrip), findsOneWidget);
              expect(
                find.descendant(
                  of: find.byType(ForwardBandStrip),
                  matching: find.byType(ForwardRecipientRow),
                ),
                findsNWidgets(5),
              );
            }
            expect(tester.takeException(), isNull);

            final sectionOrder = <Key>[];
            void recordSections() {
              for (final key in [
                ForwardRecipientPicker.directSectionKey,
                ForwardRecipientPicker.throughSectionKey,
                ForwardRecipientPicker.widerExpanderKey,
                ForwardRecipientPicker.widerSectionKey,
              ]) {
                if (!sectionOrder.contains(key) &&
                    find.byKey(key).evaluate().isNotEmpty) {
                  sectionOrder.add(key);
                }
              }
            }

            recordSections();
            final chromeBuilds = <Type, int>{};
            final previousHook = debugOnRebuildDirtyWidget;
            debugOnRebuildDirtyWidget = (element, builtOnce) {
              previousHook?.call(element, builtOnce);
              final widget = element.widget;
              if (widget is ForwardBandStrip ||
                  widget is ForwardTagPicker ||
                  widget is ForwardRecipientRow &&
                      widget.host == ForwardRecipientRowHost.pickerBand) {
                chromeBuilds.update(
                  widget.runtimeType,
                  (n) => n + 1,
                  ifAbsent: () => 1,
                );
              }
            };
            try {
              final scrollable = find
                  .descendant(
                    of: find.byType(ForwardRecipientPicker),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              final position = tester
                  .state<ScrollableState>(scrollable)
                  .position;
              final beforeDrag = position.pixels;
              final gesture = await tester.startGesture(const Offset(180, 580));
              var maxBuilds = 0;
              try {
                for (var frame = 0; frame < 16; frame++) {
                  final before = Map<String, int>.from(builds);
                  final mountedBefore = _mountedEntries();
                  await gesture.moveBy(const Offset(0, -667 / 16));
                  await tester.pump(const Duration(milliseconds: 16));
                  recordSections();
                  final mountedAfter = _mountedEntries();
                  var frameBuilds = 0;
                  for (final id in builds.keys) {
                    final delta = builds[id]! - (before[id] ?? 0);
                    frameBuilds += delta;
                    if (delta > 0 &&
                        mountedBefore.containsKey(id) &&
                        identical(mountedBefore[id], mountedAfter[id])) {
                      failures.add(
                        'frame $frame rebuilt mounted row $id $delta times',
                      );
                    }
                  }
                  if (frameBuilds > maxBuilds) maxBuilds = frameBuilds;
                  if (frameBuilds > 15) {
                    failures.add(
                      'frame $frame built $frameBuilds rows (limit 15)',
                    );
                  }
                }
              } finally {
                await gesture.up();
              }
              await tester.pumpAndSettle();
              expect(
                position.pixels - beforeDrag,
                greaterThan(600),
                reason:
                    'the measured drag must actually scroll one phone viewport',
              );

              Future<void> reveal(Finder target) async {
                // Fixed iteration bound: a missing target cannot hang this test.
                for (
                  var step = 0;
                  step < 350 && target.evaluate().isEmpty;
                  step++
                ) {
                  await tester.dragFrom(
                    const Offset(180, 580),
                    const Offset(0, -400),
                  );
                  await tester.pump(const Duration(milliseconds: 16));
                  recordSections();
                }
                expect(
                  target,
                  findsOneWidget,
                  reason: 'recipient list must reach $target',
                );
                await tester.ensureVisible(target);
                await tester.pumpAndSettle();
                recordSections();
                expect(tester.takeException(), isNull);
              }

              expect(
                find.byKey(TestIds.key(TestIds.forwardRecipient(_id(250)))),
                findsNothing,
              );
              final expander = find.byKey(
                ForwardRecipientPicker.widerExpanderKey,
              );
              await reveal(expander);
              expect(sectionOrder, [
                ForwardRecipientPicker.directSectionKey,
                ForwardRecipientPicker.throughSectionKey,
                ForwardRecipientPicker.widerExpanderKey,
              ]);
              expect(
                chromeBuilds,
                isEmpty,
                reason:
                    'scrolling to the wider-network expander must keep chrome stable',
              );
              await tester.tap(expander);
              await tester.pumpAndSettle();
              // Expanding deliberately changes the list. Start the next
              // scroll-only chrome measurement after that rebuild settles.
              chromeBuilds.clear();
              await reveal(find.byKey(ForwardRecipientPicker.widerSectionKey));
              expect(sectionOrder, [
                ForwardRecipientPicker.directSectionKey,
                ForwardRecipientPicker.throughSectionKey,
                ForwardRecipientPicker.widerExpanderKey,
                ForwardRecipientPicker.widerSectionKey,
              ]);

              final lastId = cubit.state.visibleRecipients.last.id;
              expect(
                lastId,
                cubit.state.candidates.last.id,
                reason:
                    'the final loaded candidate must remain at the bottom after expansion',
              );
              expect(cubit.state.bandMemberIds, isNot(contains(lastId)));
              final last = find.byKey(
                TestIds.key(TestIds.forwardRecipient(lastId)),
              );
              await reveal(last);
              expect(last.hitTestable(), findsOneWidget);
              expect(
                chromeBuilds,
                isEmpty,
                reason:
                    'scrolling must not rebuild the band, its rows or tag picker',
              );
              final beforeToggle = Map<String, int>.from(builds);
              expect(cubit.state.selectedIds, isNot(contains(lastId)));
              await tester.tap(
                find.byKey(
                  TestIds.key(TestIds.forwardRecipientCheckbox(lastId)),
                ),
              );
              await tester.pumpAndSettle();
              expect(cubit.state.selectedIds, contains(lastId));
              final rebuilt = builds.keys
                  .where((id) => builds[id] != beforeToggle[id])
                  .toList();
              if (rebuilt.length != 1 || rebuilt.single != lastId) {
                failures.add(
                  'selecting $lastId rebuilt $rebuilt; only the toggled id may rebuild',
                );
              }
              final beforeDeselect = Map<String, int>.from(builds);
              await tester.tap(
                find.byKey(
                  TestIds.key(TestIds.forwardRecipientCheckbox(lastId)),
                ),
              );
              await tester.pumpAndSettle();
              expect(cubit.state.selectedIds, isNot(contains(lastId)));
              final rebuiltOnDeselect = builds.keys
                  .where((id) => builds[id] != beforeDeselect[id])
                  .toList();
              if (rebuiltOnDeselect.length != 1 ||
                  rebuiltOnDeselect.single != lastId) {
                failures.add(
                  'deselecting $lastId rebuilt $rebuiltOnDeselect; '
                  'only the toggled id may rebuild',
                );
              }
              expect(tester.takeException(), isNull);
              debugPrint(
                'scroll budget: selectedWithBand=$selectedWithBand '
                'initial=$initialCount maxPerFrame=$maxBuilds violations=$failures',
              );
              expect(failures, isEmpty);
            } finally {
              debugOnRebuildDirtyWidget = previousHook;
            }
          },
        );
      },
    );
  }
}
