import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/constellation_tag_filter.dart';
import '../../domain/entity/constellation_field.dart';

export '../../domain/constellation_tag_filter.dart';

Set<String> _noOwnTags(String personId) => const {};

/// Screen-scoped tag filter of the Field. Kept apart from the field cubit so
/// selecting a tag never recomposes or re-lays out the field.
class ConstellationTagLensCubit extends Cubit<ConstellationTagFilter> {
  ConstellationTagLensCubit({this.ownTagIdsOf = _noOwnTags})
    : super(const ConstellationTagFilter());

  /// A person's own tag ids, from the tag store index.
  final Set<String> Function(String personId) ownTagIdsOf;

  /// A fresh cubit still emits its first equal state; skip every no-op.
  void _set(ConstellationTagFilter next) {
    if (isClosed || next == state) return;
    emit(next);
  }

  void toggleOwn(String tagId) {
    final next = {...state.selectedOwn};
    if (!next.remove(tagId)) next.add(tagId);
    _set(
      ConstellationTagFilter(
        selectedOwn: next,
        selectedAuto: state.selectedAuto,
        mode: state.mode,
      ),
    );
  }

  void toggleAuto(ConstellationAutoTagKind kind) {
    final next = {...state.selectedAuto};
    if (!next.remove(kind)) next.add(kind);
    _set(
      ConstellationTagFilter(
        selectedOwn: state.selectedOwn,
        selectedAuto: next,
        mode: state.mode,
      ),
    );
  }

  void setMode(ConstellationTagFilterMode mode) {
    if (isClosed) return;
    _set(
      ConstellationTagFilter(
        selectedOwn: state.selectedOwn,
        selectedAuto: state.selectedAuto,
        mode: mode,
      ),
    );
  }

  void clear() {
    _set(const ConstellationTagFilter());
  }
}

/// The tag lens of this subtree, or null where none is provided.
ConstellationTagLensCubit? maybeConstellationTagLens(BuildContext context) {
  try {
    return context.read<ConstellationTagLensCubit>();
  } on ProviderNotFoundException {
    return null;
  }
}
