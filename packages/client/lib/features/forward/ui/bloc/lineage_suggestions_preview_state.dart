import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/lineage_suggestion_group.dart';

class LineageSuggestionsPreviewState extends StateBase {
  const LineageSuggestionsPreviewState({
    this.beaconId = '',
    this.rows = const [],
    this.loadError,
    super.status = const StateIsSuccess(),
  });

  final String beaconId;
  final List<LineagePreviewRow> rows;
  final Object? loadError;

  bool get hasError => loadError != null;

  LineageSuggestionsPreviewState copyWith({
    String? beaconId,
    List<LineagePreviewRow>? rows,
    StateStatus? status,
    Object? loadError,
    bool clearLoadError = false,
  }) =>
      LineageSuggestionsPreviewState(
        beaconId: beaconId ?? this.beaconId,
        rows: rows ?? this.rows,
        status: status ?? this.status,
        loadError: clearLoadError ? null : (loadError ?? this.loadError),
      );
}
