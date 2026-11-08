import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_progress.dart';

const kMyWorkFirstLoadSteps = 3;

FirstLoadProgress? myWorkFirstLoadProgress(MyWorkState state, L10n l10n) {
  if (state.firstLoadDone) return null;
  if (state.nonArchivedProjectionLoaded) {
    return FirstLoadProgress(
      step: 3,
      totalSteps: kMyWorkFirstLoadSteps,
      stageLabel: l10n.firstLoadStageMyWorkAttention,
    );
  }
  if (state.deskInitLoaded) {
    return FirstLoadProgress(
      step: 2,
      totalSteps: kMyWorkFirstLoadSteps,
      stageLabel: l10n.firstLoadStageMyWorkClosure,
    );
  }
  return FirstLoadProgress(
    step: 1,
    totalSteps: kMyWorkFirstLoadSteps,
    stageLabel: l10n.firstLoadStageMyWorkDesk,
  );
}
