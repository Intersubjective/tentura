import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_activity_event_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_activity_sheet.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

// Adapt the existing case harness's concrete fake parameter while delegating
// the activity read entirely to the production repository and Ferry mapper.
class _WireActivityRepository extends FakeBeaconViewActivityEventRepository {
  _WireActivityRepository(this.repository);
  final BeaconActivityEventRepository repository;

  @override
  Future<List<BeaconActivityEvent>> list({required String beaconId}) =>
      repository.list(beaconId: beaconId);
}

void main() {
  for (final language in ['ru', 'en']) {
    testWidgets(
      'Log retains reviewed history and distinguishes a two-helper immediate close in $language',
      (tester) async {
        if (language == 'ru') {
          await usePhoneSurface(tester);
        } else {
          await tester.binding.setSurfaceSize(const Size(1280, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
        }
        // Review history is checked at desktop width; the phone case covers
        // the two-helper immediate close, including full RU copy.
        for (final scenario in <({String? openedReason, bool hadReview})>[
          if (language == 'en')
            for (final reason in [
              BeaconLifecycleChangeReason.closureOpened,
              BeaconLifecycleChangeReason.legacyClosureOpenReason,
            ]) ...[
              (openedReason: reason, hadReview: true),
              (openedReason: reason, hadReview: false),
            ],
          (openedReason: null, hadReview: false),
        ]) {
          final openedReason = scenario.openedReason;
          final hadReview = scenario.hadReview;
          final sent = <WireSent>[];
          await withRemoteWire(
            {
              'BeaconActivityEventList': {
                'BeaconActivityEventList': [
                  if (openedReason != null)
                    {
                      'id': 'opened',
                      'beaconId': 'BmovingDay',
                      'visibility': 0,
                      'type':
                          BeaconActivityEventTypeBits.beaconLifecycleChanged,
                      'actorId': null,
                      'targetUserId': null,
                      'sourceMessageId': null,
                      'coordinationItemId': null,
                      'createdAt': '2026-11-02T12:00:00Z',
                      'diffJson': jsonEncode({
                        'fromState': BeaconStatus.enoughHelp.smallintValue,
                        'toState': BeaconStatus.reviewOpen.smallintValue,
                        'reason': openedReason,
                      }),
                    },
                  {
                    'id': 'close',
                    'beaconId': 'BmovingDay',
                    'visibility': 0,
                    'type': BeaconActivityEventTypeBits.beaconLifecycleChanged,
                    'actorId': null,
                    'targetUserId': null,
                    'sourceMessageId': null,
                    'coordinationItemId': null,
                    'createdAt': '2026-11-03T12:00:00Z',
                    'diffJson': jsonEncode({
                      'fromState': openedReason != null
                          ? BeaconStatus.reviewOpen.smallintValue
                          : BeaconStatus.enoughHelp.smallintValue,
                      'toState': 6,
                      'reason': 'authorCloseNow',
                    }),
                  },
                ],
              },
              'ClosureState': {
                'closureState': {
                  'epoch': 1,
                  'status': 1,
                  'role': 'author',
                  'members': [
                    for (final name in ['Bob', 'Carol', if (hadReview) 'Dave'])
                      {
                        'id': name,
                        'displayName': name,
                        'avatarId': null,
                        'helpTypes': null,
                        'offerText': null,
                        'notInRequest': false,
                        'departure': null,
                      },
                  ],
                  'outcomes': null,
                  'split': null,
                  'mySupport': <String>[],
                  'inCalcText': null,
                  'myMarks': <String>[],
                  'closesAt': '2026-11-03T12:00:00Z',
                  'earlyCloseAt': hadReview ? '2026-11-02T13:00:00Z' : null,
                  'canCloseNow': false,
                  'canReopen': false,
                  'extensionsUsed': 0,
                  'story': null,
                },
              },
            },
            sent,
            (remote) async {
              final realtime = buildTestRealtimeSync();
              final activity = BeaconActivityEventRepository(
                remote,
                realtime.port,
              );
              final beaconRepo = TrackingBeaconRepository()
                ..fetchByIdHandler = (_) async => Beacon(
                  id: 'BmovingDay',
                  title: 'Moving day',
                  author: const Profile(id: 'author', displayName: 'Alice'),
                  createdAt: DateTime.utc(2026, 11, 3),
                  updatedAt: DateTime.utc(2026, 11, 3, 12),
                  status: BeaconStatus.closed,
                );
              final effects = FakeUiEffectPort();
              late BeaconViewCubit cubit;
              await tester.runAsync(() async {
                cubit = BeaconViewCubit(
                  id: 'BmovingDay',
                  myProfile: const Profile(id: 'author', displayName: 'Alice'),
                  beaconViewCase: buildTestBeaconViewCase(
                    beaconRepo: beaconRepo,
                    closureRepo: ClosureRepository(remote),
                    activityEventsRepo: _WireActivityRepository(activity),
                    realtimeSyncCase: realtime.case_,
                  ),
                  effects: effects,
                );
                await cubit.stream
                    .firstWhere((s) => s.beaconContextLoaded)
                    .timeout(const Duration(seconds: 5));
              });
              addTearDown(() async {
                await cubit.close();
                await activity.dispose();
                await beaconRepo.dispose();
                await realtime.port.dispose();
              });
              // Prove both real wire reads arrived before asserting UI copy.
              expect(
                cubit.state.roomActivityEvents,
                hasLength(openedReason != null ? 2 : 1),
              );
              expect(
                cubit.state.closureState?.members,
                hasLength(hadReview ? 3 : 2),
              );
              expect(cubit.state.beacon.status, BeaconStatus.closed);
              expect(cubit.state.closureState?.status, 1);
              expect(cubit.state.closureState?.hadNoFinalCheck, !hadReview);
              expect(effects.emitted, isEmpty);
              expect(
                sent.map((s) => s.operationName),
                containsAll([
                  'BeaconActivityEventList',
                  'ClosureState',
                ]),
              );

              await tester.pumpWidget(
                MaterialApp(
                  locale: Locale(language),
                  theme: TenturaTheme.light(),
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  home: TenturaResponsiveScope(
                    child: Scaffold(
                      body: Builder(
                        builder: (context) => Center(
                          child: BeaconOverflowMenu(
                            beacon: cubit.state.beacon,
                            onActivityLog: () => showBeaconActivitySheet(
                              context,
                              cubit: cubit,
                              onTapCoordinationEvent: (_) {},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final l10n = lookupL10n(Locale(language));
              await tester.tap(
                find.byKey(TestIds.key(TestIds.beaconOverflowMenu)),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text(l10n.labelBeaconTabLog).last);
              await tester.pumpAndSettle();
              expect(find.text(l10n.labelBeaconTabLog), findsOneWidget);
              expect(
                find.text(l10n.beaconLifecycleReviewOpen),
                hadReview ? findsOneWidget : findsNothing,
                reason: 'A real final check remains in the Log: $openedReason',
              );
              final closeLabel = hadReview
                  ? l10n.beaconActivityLifecycleClosedAfterReview
                  : l10n.beaconLifecycleClosed;
              expect(find.text(closeLabel), findsOneWidget);
              expect(
                find.text(
                  hadReview
                      ? l10n.beaconLifecycleClosed
                      : l10n.beaconActivityLifecycleClosedAfterReview,
                ),
                findsNothing,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.text(closeLabel),
              );
              expect(paragraph.didExceedMaxLines, isFalse);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      },
    );
  }
}
