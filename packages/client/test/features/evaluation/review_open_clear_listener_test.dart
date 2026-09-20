import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/evaluation/domain/use_case/evaluation_case.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/features/evaluation/ui/widget/review_open_clear_listener.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'evaluation_case_test.dart' show FakeEvaluationRepository;

void main() {
  const beaconId = 'Breview';

  /// Mounts the production listener over a real [EvaluationCubit], so the
  /// success/failure signal is the cubit's own.
  Future<({List<String> clears, EvaluationCubit cubit})> mount(
    WidgetTester tester,
    FakeEvaluationRepository repository,
  ) async {
    final clears = <String>[];
    final cubit = EvaluationCubit(
      EvaluationCase(
        repository,
        env: const Env(),
        logger: Logger('review-open-clear-test'),
      ),
      beaconId: beaconId,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<EvaluationCubit>.value(
          value: cubit,
          child: ReviewOpenClearListener(
            beaconId: beaconId,
            clear: ({required String beaconId}) async => clears.add(beaconId),
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await cubit.loadParticipantsOnly();
    await tester.pumpAndSettle();
    return (clears: clears, cubit: cubit);
  }

  testWidgets('a review deep link that displays clears that Request', (
    tester,
  ) async {
    final repository = FakeEvaluationRepository()
      ..reviewWindowResult = ReviewWindowInfo(
        beaconId: beaconId,
        hasWindow: true,
      );
    final r = await mount(tester, repository);

    expect(repository.lastParticipantsBeaconId, beaconId);
    expect(r.cubit.state.reviewContentLoaded, isTrue);
    expect(r.clears, [beaconId]);
  });

  testWidgets('a review screen whose load failed clears nothing', (
    tester,
  ) async {
    final repository = _FailingEvaluationRepository();
    final r = await mount(tester, repository);

    // The failure path was genuinely exercised: the load ran and threw.
    expect(repository.participantCalls, 1);
    expect(r.cubit.state.reviewContentLoaded, isFalse);
    expect(r.clears, isEmpty);
  });

  testWidgets('re-reading the package after a send clears nothing more', (
    tester,
  ) async {
    final repository = FakeEvaluationRepository()
      ..reviewWindowResult = ReviewWindowInfo(
        beaconId: beaconId,
        hasWindow: true,
      );
    final r = await mount(tester, repository);
    expect(r.clears, [beaconId]);

    // A second successful read is a refresh, not an opening (§4).
    await r.cubit.loadParticipantsOnly();
    await tester.pumpAndSettle();

    expect(r.clears, [beaconId]);
  });
}

class _FailingEvaluationRepository extends FakeEvaluationRepository {
  int participantCalls = 0;

  @override
  Future<List<EvaluationParticipant>> fetchParticipants(String beaconId) async {
    participantCalls++;
    throw StateError('forbidden');
  }
}
