import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/person_forward_row.dart';
import 'package:tentura/features/forward/ui/bloc/person_forward_cubit.dart';
import 'package:tentura/features/forward/ui/screen/person_forward_screen.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _RecordingScreenCubit extends ScreenCubit {
  _RecordingScreenCubit() : super(FakeUiEffectPort());

  String? lastCreateForUserId;

  @override
  void showBeaconCreateFor(String userId) {
    lastCreateForUserId = userId;
  }
}

Future<void> _pumpPersonForwardPage(
  WidgetTester tester, {
  required PersonForwardCubit cubit,
  ScreenCubit? screenCubit,
  Size size = const Size(400, 900),
}) async {
  final screen = screenCubit ?? _RecordingScreenCubit();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<PersonForwardCubit>.value(value: cubit),
              BlocProvider<ScreenCubit>.value(value: screen),
            ],
            child: Scaffold(
              body: BlocBuilder<PersonForwardCubit, PersonForwardState>(
                builder: (context, state) =>
                    personForwardBodyForTest(state: state),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Profile _reachablePerson({
  Availability availability = const Availability(),
}) =>
    Profile(
      id: 'U-target',
      displayName: 'Ada',
      score: 1,
      rScore: 1,
      availability: availability,
    );

Beacon _openBeacon() => Beacon.empty.copyWith(
  id: 'B-open',
  title: 'Help moving',
  author: const Profile(id: 'U-me'),
);

PersonForwardRow _eligibleRow() => PersonForwardRow(
  beacon: _openBeacon(),
  involvement: CandidateInvolvement.unseen,
);

void main() {
  group('PersonForwardScreen availability gate', () {
    testWidgets('direct deep link shows paused banner and disables actions',
        (tester) async {
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
        clock: () => DateTime.utc(2026, 8, 14, 12),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: _reachablePerson(
            availability: Availability(
              resumeOn: DateTime.utc(2026, 8, 20),
            ),
          ),
          rows: [_eligibleRow()],
          selectedBeaconId: 'B-open',
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(tester, cubit: cubit);

      expect(
        find.textContaining('isn\'t taking new requests until'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    });

    testWidgets('existing request keeps send enabled when open', (tester) async {
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: _reachablePerson(),
          rows: [_eligibleRow()],
          selectedBeaconId: 'B-open',
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(tester, cubit: cubit);
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.beaconForwardPersonSend), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('new request path stays enabled for limited person', (tester) async {
      final screenCubit = _RecordingScreenCubit();
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: _reachablePerson(
            availability: const Availability(isLimited: true),
          ),
          rows: const [],
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(
        tester,
        cubit: cubit,
        screenCubit: screenCubit,
      );
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.availabilityLimitedTitle), findsOneWidget);
      final newRequest = tester.widget<TextButton>(find.byType(TextButton));
      expect(newRequest.onPressed, isNotNull);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(screenCubit.lastCreateForUserId, 'U-target');
    });

    testWidgets('resume-day equality hides paused banner and enables send',
        (tester) async {
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
        clock: () => DateTime.utc(2026, 8, 20, 12),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: _reachablePerson(
            availability: Availability(
              resumeOn: DateTime.utc(2026, 8, 20),
            ),
          ),
          rows: [_eligibleRow()],
          selectedBeaconId: 'B-open',
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(tester, cubit: cubit);

      expect(find.textContaining('isn\'t taking new requests until'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('empty state disables new request while paused', (tester) async {
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
        clock: () => DateTime.utc(2026, 8, 14, 12),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: _reachablePerson(
            availability: Availability(
              resumeOn: DateTime.utc(2026, 8, 20),
            ),
          ),
          rows: const [],
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(tester, cubit: cubit);

      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    });

    testWidgets('unreachable person keeps lifecycle banner without send',
        (tester) async {
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: const Profile(
            id: 'U-target',
            displayName: 'Ada',
            myVote: 1,
          ),
          rows: [_eligibleRow()],
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(tester, cubit: cubit);
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.beaconForwardPersonUnreachable('Ada')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('already-sent block keeps row subtitle without enabling send',
        (tester) async {
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: _reachablePerson(),
          rows: [
            _eligibleRow().copyWith(block: PersonForwardBlock.alreadySent),
          ],
          selectedBeaconId: 'B-open',
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(tester, cubit: cubit);
      final l10n = lookupL10n(const Locale('en'));

      expect(
        find.text(l10n.beaconForwardPersonReasonAlreadySent),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('already-sent cancellable row shows cancel and edit actions',
        (tester) async {
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: _reachablePerson(),
          rows: [
            _eligibleRow().copyWith(
              block: PersonForwardBlock.alreadySent,
              forwardEdgeId: 'edge-1',
            ),
          ],
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(tester, cubit: cubit);
      final l10n = lookupL10n(const Locale('en'));

      expect(find.byTooltip(l10n.forwardCancelAction), findsOneWidget);
      expect(find.byTooltip(l10n.forwardEditAction), findsOneWidget);
    });

    testWidgets('empty note send shows uncovered sheet', (tester) async {
      final cubit = PersonForwardCubit(
        personId: 'U-target',
        debugSkipInitialLoad: true,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      cubit.emit(
        PersonForwardState(
          personId: 'U-target',
          person: _reachablePerson(),
          rows: [_eligibleRow()],
          selectedBeaconId: 'B-open',
          status: const StateIsSuccess(),
        ),
      );

      await _pumpPersonForwardPage(tester, cubit: cubit);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('No personal note yet'), findsOneWidget);
      expect(find.text('Send without a shared note'), findsOneWidget);
    });
  });
}
