import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/constellation_multi_selection.dart';

export '../../domain/constellation_multi_selection.dart';

/// Screen-scoped Field multi-selection (#642) and the sector being aimed for
/// «Arrange in sector» (#644). Kept apart from the field cubit so selecting
/// never recomposes or re-lays out the field.
class ConstellationSelectionCubit extends Cubit<ConstellationMultiSelection> {
  ConstellationSelectionCubit() : super(ConstellationMultiSelection.empty);

  /// Whether a pointer tap now adds to the selection on desktop: Shift, Ctrl
  /// or Cmd is held.
  static bool get modifierHeld {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;
  }

  /// The select tool (toolbar toggle, «Done»). Turning it off keeps what
  /// is selected for the bulk actions.
  void setSelecting(bool selecting) {
    if (isClosed) return;
    emit(state.withSelecting(selecting));
  }

  void toggle(ConstellationAnchorTarget target) {
    if (isClosed) return;
    emit(state.toggle(target));
  }

  void addAll(Iterable<ConstellationAnchorTarget> targets) {
    if (isClosed) return;
    emit(state.addAll(targets));
  }

  /// A finished rubber-band box (#642).
  void applyBox(
    Iterable<ConstellationAnchorTarget> inside,
    ConstellationBoxMerge merge,
  ) {
    if (isClosed) return;
    emit(state.applyBox(inside, merge));
  }

  /// «Clear selection»: nothing selected and the toolbar toggle off.
  void clear() {
    if (isClosed) return;
    emit(ConstellationMultiSelection.empty);
  }

  void beginSector({required double direction}) {
    if (isClosed || !state.canArrange) return;
    emit(
      state.withSector(
        const ConstellationSectorDraft(direction: 0).copyWith(
          direction: direction,
        ),
      ),
    );
  }

  void aimSector({double? direction, double? span}) {
    final sector = state.sector;
    if (isClosed || sector == null) return;
    emit(state.withSector(sector.copyWith(direction: direction, span: span)));
  }

  void cancelSector() {
    if (isClosed || state.sector == null) return;
    emit(state.withSector(null));
  }

  /// Escape steps back once: the sector being aimed, then the selection.
  /// False when there was nothing to undo.
  bool escape() {
    if (isClosed) return false;
    if (state.sector != null) {
      cancelSector();
      return true;
    }
    if (state.isActive) {
      clear();
      return true;
    }
    return false;
  }
}

/// The selection of this subtree, or null where none is provided.
ConstellationSelectionCubit? maybeConstellationSelection(BuildContext context) {
  try {
    return context.read<ConstellationSelectionCubit>();
  } on ProviderNotFoundException {
    return null;
  }
}
