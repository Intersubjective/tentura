// #825: with fewer than three helpers the HUD closes now, from the server's
// display status ([closureFinalCheckHasNoVote]). The status sheet used to
// offer Final check and grey out Closed. After a Close now, a helper's
// result is the server's answer (no review window), not «could not judge»,
// and the discussion does not record a Final check step.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_status_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu.dart';
import 'package:tentura/features/beacon_view/domain/beacon_status_menu_presenter.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/closure/ui/widget/closure_result_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_activity_event_presenter.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

final _t = DateTime.utc(2026, 10, 30, 12);
final _en = lookupL10n(const Locale('en'));
final _ru = lookupL10n(const Locale('ru'));

Beacon _beacon(BeaconStatus status) => Beacon(
  id: 'B825',
  title: 'Two helpers',
  author: const Profile(id: 'uAuthor', displayName: 'Alice'),
  createdAt: _t,
  updatedAt: _t,
  status: status,
);

BeaconStatusMenuInput _input({
  required bool closesWithoutFinalCheck,
  bool hasCommitters = true,
  BeaconStatus status = BeaconStatus.enoughHelp,
}) => BeaconStatusMenuInput(
  beacon: _beacon(status),
  closureReadiness: BeaconClosureReadiness.readyToClose,
  hasCommitters: hasCommitters,
  canManageLifecycle: true,
  canSetCoordination: true,
  closesWithoutFinalCheck: closesWithoutFinalCheck,
);

BeaconStatusMenuRow _row(
  List<BeaconStatusMenuRow> rows,
  BeaconStatusMenuRowId id,
) => rows.firstWhere((row) => row.id == id);

class _MockCubit extends Mock implements BeaconViewCubit {
  _MockCubit(this._state);

  final BeaconViewState _state;
  int closeNowCalls = 0;

  @override
  BeaconViewState get state => _state;

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);

  @override
  Future<void> closeBeaconNow() async => closeNowCalls++;
}

void _expectWholeLine(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'cut: $text');
  expect(tester.takeException(), isNull);
}

void main() {
  group('status sheet uses the HUD close-now rule', () {
    test('Closed is enabled and Final check explains it closes right away', () {
      final rows = buildBeaconStatusMenuRows(
        _input(closesWithoutFinalCheck: true),
      );
      final closed = _row(rows, BeaconStatusMenuRowId.closed);
      final wrapping = _row(rows, BeaconStatusMenuRowId.wrappingUp);
      expect(closed.isEnabled, isTrue);
      expect(closed.action, BeaconStatusMenuAction.closeWithoutFinalCheck);
      expect(wrapping.isEnabled, isFalse);
      expect(
        wrapping.disabledReason,
        BeaconStatusMenuDisabledReason.closesWithoutFinalCheck,
      );
      expect(
        beaconStatusMenuDisabledReasonLabel(_en, wrapping.disabledReason),
        _en.beaconHudActEffectWrapUpNoVote,
      );
    });

    test('three or more helpers still wait for the final check', () {
      final rows = buildBeaconStatusMenuRows(
        _input(closesWithoutFinalCheck: false),
      );
      expect(_row(rows, BeaconStatusMenuRowId.closed).isEnabled, isFalse);
      expect(
        _row(rows, BeaconStatusMenuRowId.closed).disabledReason,
        BeaconStatusMenuDisabledReason.finishReviewFirst,
      );
      expect(_row(rows, BeaconStatusMenuRowId.wrappingUp).isEnabled, isTrue);
    });

    testWidgets(
      'Closed runs the HUD close sheet, not Close now during review',
      (
        tester,
      ) async {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: TenturaResponsiveScope(
              child: Scaffold(
                body: Builder(
                  builder: (ctx) {
                    context = ctx;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        );
        final state = BeaconViewState(
          beacon: _beacon(BeaconStatus.enoughHelp),
          myProfile: const Profile(id: 'uAuthor', displayName: 'Alice'),
          beaconContextLoaded: true,
          displayStatus: const BeaconDisplayStatusDto(
            beaconId: 'B825',
            status: BeaconStatus.enoughHelp,
            phase: BeaconCoordinationPhase.enoughHelpInMotion,
            suggestedAction: BeaconPhasePrimaryAction.none,
            slot2Kind: BeaconPhaseSlot2Kind.none,
            tier: BeaconDisplayTier.coordination,
            everAcknowledgedCommitterCount: 2,
          ),
        );
        final cubit = _MockCubit(state);
        final done = beaconViewDispatchStatusMenuAction(
          context,
          action: BeaconStatusMenuAction.closeWithoutFinalCheck,
          state: state,
          cubit: cubit,
          l10n: _en,
          onOpenPeopleTab: () {},
          onOpenGeneralThread: () {},
        );
        await tester.pumpAndSettle();
        expect(find.text(_en.beaconCloseSheetNoVoteBody), findsOneWidget);
        expect(find.text(_en.beaconReviewCloseNowBody), findsNothing);
        expect(cubit.closeNowCalls, 0);
        final dismiss = find.text(_en.beaconCloseSheetActionNotNow);
        await tester.tap(
          dismiss.evaluate().isNotEmpty
              ? dismiss
              : find.text(_en.beaconCloseSheetActionKeepActive),
        );
        await tester.pumpAndSettle();
        await done;
      },
    );

    testWidgets('the Russian sheet fits a 375×667 phone', (tester) async {
      await usePhoneSurface(tester);
      final rows = buildBeaconStatusMenuRows(
        _input(closesWithoutFinalCheck: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: ListView(
                children: [
                  for (final row in rows)
                    BeaconStatusMenuRowTile(
                      row: row,
                      beacon: _beacon(BeaconStatus.enoughHelp),
                      isLoading: false,
                      onTap: row.isEnabled ? () {} : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectWholeLine(tester, _ru.beaconStatusRowClosed);
      _expectWholeLine(tester, _ru.beaconHudActEffectWrapUpNoVote);
      expect(find.text(_ru.beaconStatusHintFinishReviewFirst), findsNothing);
    });
  });

  group('helper result after Close now', () {
    test('a voter with no review window is not a judged result', () {
      final state = ClosureState(
        epoch: 1,
        status: 1,
        role: ClosureRole.voter,
        members: const [],
        closesAt: _t,
      );
      expect(state.hadNoFinalCheck, isTrue);
      final reviewed = ClosureState(
        epoch: 1,
        status: 1,
        role: ClosureRole.voter,
        members: const [],
        closesAt: _t,
        earlyCloseAt: _t,
      );
      expect(reviewed.hadNoFinalCheck, isFalse);
    });

    testWidgets(
      'the card reads the server result, not a could-not-judge mark',
      (tester) async {
        final sent = <WireSent>[];
        await withRemoteWire(
          {
            'ClosureResultForViewer': {
              '__typename': 'query_root',
              'closureResultForViewer': {
                '__typename': 'ClosureResult',
                'outcome': 'cantJudge',
                'band': 'asIfSilent',
                'draftFlag': 'none',
                'marks': <String>[],
                'story': null,
                'unjudgedLeaver': false,
              },
            },
            'ClosureState': {
              '__typename': 'query_root',
              'closureState': {
                '__typename': 'ClosureState',
                'epoch': 1,
                'status': 1,
                'role': 'voter',
                'members': [
                  {
                    '__typename': 'ClosureMember',
                    'id': 'uBob',
                    'displayName': 'Bob',
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
                'closesAt': '2026-10-30T12:00:00.000Z',
                'earlyCloseAt': null,
                'canCloseNow': false,
                'canReopen': false,
                'extensionsUsed': 0,
                'story': null,
              },
            },
          },
          sent,
          (remote) async {
            await usePhoneSurface(tester);
            GetIt.I.registerSingleton<ClosureCase>(
              ClosureCase(
                ClosureRepository(remote),
                env: const Env(),
                logger: Logger('test'),
              ),
            );
            addTearDown(() async {
              if (GetIt.I.isRegistered<ClosureCase>()) {
                await GetIt.I.unregister<ClosureCase>();
              }
            });
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('ru'),
                theme: TenturaTheme.light(),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: const TenturaResponsiveScope(
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: ClosureResultCard(
                        beaconId: 'B825',
                        viewerId: 'uBob',
                        author: ClosureMember(
                          id: 'uAuthor',
                          displayName: 'Alice',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            _expectWholeLine(tester, _ru.closureResultClosedWithoutFinalCheck);
            expect(find.text(_ru.closureResultOutcomeCantJudge), findsNothing);
            expect(find.text(_ru.closureResultBandAsIfSilent), findsNothing);
            expect(
              sent.map((call) => call.operationName),
              contains('ClosureResultForViewer'),
            );
          },
        );
      },
    );
  });

  group('log omits the skipped final check', () {
    RoomMessage statusLine({
      required String id,
      required int from,
      required int to,
      required String reason,
    }) => RoomMessage(
      id: id,
      beaconId: 'B825',
      authorId: 'uAuthor',
      author: const Profile(id: 'uAuthor', displayName: 'Alice'),
      body: '',
      createdAt: _t,
      systemMessageKind: 7,
      systemPayloadJson:
          '{"version":1,"fromStatus":$from,"toStatus":$to,"reason":"$reason"}',
    );

    test(
      'Enough help → Final check disappears and the close starts earlier',
      () {
        final lines = omitSkippedFinalCheckStatusLines([
          statusLine(id: 'open', from: 8, to: 5, reason: 'closureOpened'),
          statusLine(id: 'close', from: 5, to: 6, reason: 'authorCloseNow'),
        ]);
        expect(lines, hasLength(1));
        final change = RoomStatusChange.fromMessage(lines.single)!;
        expect(change.from, BeaconStatus.enoughHelp);
        expect(change.to, BeaconStatus.closed);
        expect(change.reason, 'authorCloseNow');
      },
    );

    test('the following close no longer reads as a final check', () {
      final opened = BeaconActivityEvent(
        id: 'open',
        beaconId: 'B825',
        visibility: 0,
        type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
        createdAt: _t,
        diffJson:
            '{"fromState":8,"toState":5,"reason":"${BeaconLifecycleChangeReason.closureOpened}"}',
      );
      final closed = BeaconActivityEvent(
        id: 'close',
        beaconId: 'B825',
        visibility: 0,
        type: BeaconActivityEventTypeBits.beaconLifecycleChanged,
        createdAt: _t.add(const Duration(days: 1)),
        diffJson:
            '{"fromState":5,"toState":6,"reason":"${BeaconLifecycleChangeReason.authorCloseNow}"}',
      );
      final kept = omitSkippedFinalCheckActivityEvents([opened, closed]);
      expect(kept, hasLength(1));
      expect(
        beaconActivityEventLabel(_en, kept.single),
        _en.beaconLifecycleClosed,
      );
      expect(
        beaconActivityEventLabel(_en, kept.single),
        isNot(_en.beaconLifecycleReviewOpen),
      );
      final decoded = jsonDecode(kept.single.diffJson!) as Map<String, dynamic>;
      expect(decoded['fromState'], 8);
      expect(decoded['reason'], BeaconLifecycleChangeReason.directClose);
    });
  });
}
