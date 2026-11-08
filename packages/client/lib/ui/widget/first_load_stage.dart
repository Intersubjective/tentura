import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_progress.dart';

const kMyWorkFirstLoadSteps = 3;
const kRequestFirstLoadSteps = 3;

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

/// Mirrors the hierarchy slice of the Request first-load gate readiness.
bool requestHierarchyBlocksFirstLoad({
  required bool showcase,
  required bool isSplit,
  required bool nowSurfaceSelected,
  required bool hierarchyLoading,
  required bool hierarchyHasCapabilities,
  required Object? hierarchyCapabilitiesError,
}) {
  if (showcase) return false;
  if (!isSplit || !nowSurfaceSelected) return false;
  return hierarchyLoading ||
      (!hierarchyHasCapabilities && hierarchyCapabilitiesError == null);
}

FirstLoadProgress? requestFirstLoadProgress({
  required L10n l10n,
  required BeaconViewState beacon,
  required bool roomExpected,
  required bool roomFirstLoadDone,
  required bool hierarchyBlocks,
}) {
  if (beacon.firstLoadDone) {
    if (roomExpected && !roomFirstLoadDone) {
      return FirstLoadProgress(
        step: 2,
        totalSteps: kRequestFirstLoadSteps,
        stageLabel: l10n.firstLoadStageRequestThread,
      );
    }
    if (hierarchyBlocks) {
      return FirstLoadProgress(
        step: 3,
        totalSteps: kRequestFirstLoadSteps,
        stageLabel: l10n.firstLoadStageRequestHierarchy,
      );
    }
    return null;
  }
  return FirstLoadProgress(
    step: 1,
    totalSteps: kRequestFirstLoadSteps,
    stageLabel: l10n.firstLoadStageRequestBeacon,
  );
}
