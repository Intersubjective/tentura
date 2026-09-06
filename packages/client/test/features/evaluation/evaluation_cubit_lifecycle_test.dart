import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/domain/use_case/evaluation_case.dart';
import 'package:tentura/features/evaluation/ui/bloc/evaluation_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'evaluation_case_test.dart' show FakeEvaluationRepository;

class _Effects implements UiEffectPort {
  final emitted = <UiEffect>[];

  @override
  Stream<UiEffect> get effects => const Stream.empty();

  @override
  void emit(UiEffect effect) => emitted.add(effect);
}

class _GatedDraftSaveRepository extends FakeEvaluationRepository {
  Completer<void>? draftSaveGate;

  @override
  Future<void> draftSave({
    required String beaconId,
    required String evaluatedUserId,
    required int value,
    List<String>? reasonTags,
    String note = '',
  }) async {
    final gate = draftSaveGate;
    if (gate != null) {
      await gate.future;
      draftSaveGate = null;
    }
    await super.draftSave(
      beaconId: beaconId,
      evaluatedUserId: evaluatedUserId,
      value: value,
      reasonTags: reasonTags,
      note: note,
    );
  }
}

void main() {
  const participant = EvaluationParticipant(
    userId: 'u1',
    displayName: 'Alice',
    role: EvaluationParticipantRole.committer,
    contributionSummary: 'Helped',
    causalHint: '',
  );

  test('draftSave completion after dispose does not emit', () async {
    final repository = _GatedDraftSaveRepository()
      ..draftParticipantsResult = [
        participant.copyWith(currentValue: EvaluationValue.pos1),
      ];
    final effects = _Effects();
    final cubit = EvaluationCubit(
      EvaluationCase(
        repository,
        env: const Env(),
        logger: Logger('evaluation-cubit-lifecycle'),
      ),
      beaconId: 'b1',
      isDraftMode: true,
      effects: effects,
    );
    repository.draftSaveGate = Completer<void>();

    final pending = cubit.submitOne(
      evaluatedUserId: 'u1',
      value: EvaluationValue.pos1,
    );
    await cubit.close();
    repository.draftSaveGate!.complete();

    expect(await pending, isTrue);
    expect(cubit.isClosed, isTrue);
    expect(repository.draftSaveCalls, 1);
    expect(effects.emitted, isEmpty);
  });
}
