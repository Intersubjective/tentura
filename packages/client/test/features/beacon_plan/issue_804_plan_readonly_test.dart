@Timeout(Duration(minutes: 2))
library;

import 'package:ferry/ferry.dart' show ServerException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/plan/plan.dart';

import 'package:tentura/app/sentry/sentry_benign_filter.dart';
import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/data/repository/beacon_plan_repository.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_edit_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/screen/plan_edit_screen.dart';
import 'package:tentura/features/beacon_plan/ui/util/plan_presenter.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import 'beacon_plan_test_support.dart';

const _readOnlyWire = {
  'message': 'The plan of this request is read-only',
  'extensions': {'code': '1338'},
};

void main() {
  group('Issue #804 plan read-only (1338)', () {
    test(
      'BeaconPlanSave 1338 crosses the wire as PlanNotEditableException',
      () async {
        Object? caught;
      await withRemoteWire(
        const {},
        <WireSent>[],
        (remote) async {
          final repo = BeaconPlanRepository(remote, TestRealtimeSyncPort());
          try {
            await repo.save(
              beaconId: 'B1',
              baseRevisionSeq: 0,
              steps: PlanSnapshot.empty,
            );
          } catch (error) {
            caught = error;
          } finally {
            await repo.dispose();
          }
        },
        errors: {'BeaconPlanSave': _readOnlyWire},
      );
        expect(caught, isA<PlanNotEditableException>());
        expect(
          planErrorText(caught!, lookupL10n(const Locale('en'))),
          "The plan can't be changed now",
        );
      },
    );

    test(
      'mapRemoteFailure keeps PlanNotEditableException through ServerException',
      () {
        const original = PlanNotEditableException();
        expect(mapRemoteFailure(original), same(original));
        expect(
          mapRemoteFailure(
            const ServerException(originalException: original),
          ),
          same(original),
        );
      },
    );

    test('1338 is benign for Sentry', () {
      expect(isBenignSentryThrowable(const PlanNotEditableException()), isTrue);
    });

    testWidgets(
      'RU snackbar at 375×667 shows planErrorNotEditable, not the class name',
      (
        tester,
      ) async {
        GetIt.I.registerSingleton<Logger>(Logger('issue804-plan-readonly'));
        addTearDown(GetIt.I.reset);
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exceptionAsString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);
        await usePhoneSurface(tester);
        final repo = FakeBeaconPlanRepository(
          const BeaconPlan(
            beaconId: 'B1',
            editable: true,
            tickable: true,
            revisionSeq: 1,
          ),
        );
        repo.saveErrors.add(const PlanNotEditableException());
        final cubit = PlanEditCubit(
          plan: repo.plan,
          planCase: planCaseFor(repo),
        );
        addTearDown(cubit.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('ru'),
            home: BlocProvider.value(
              value: cubit,
              child: PlanEditScreen(
                people: PlanPeople(admitted: []),
                onClose: () {},
                onSaved: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        cubit.putStep(
          const PlanStepSnapshot(id: 'PS1', title: 'QA step'),
        );
        await cubit.save();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(cubit.state.error, isA<PlanNotEditableException>());
        final snack = find.byType(SnackBar);
        expect(snack, findsOneWidget);
        final message = tester
            .widgetList<RichText>(
              find.descendant(of: snack, matching: find.byType(RichText)),
            )
            .map((w) => w.text.toPlainText())
            .join();
        final expected = lookupL10n(const Locale('ru')).planErrorNotEditable;
        expect(message, startsWith(expected));
        expect(message, isNot(contains('BeaconPlanException')));
      },
    );
  });
}
