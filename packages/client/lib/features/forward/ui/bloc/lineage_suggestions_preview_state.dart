import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/lineage_suggestion_group.dart';

class LineageSuggestionsPreviewState extends StateBase {
  const LineageSuggestionsPreviewState({
    this.beaconId = '',
    this.rows = const [],
    super.status = const StateIsSuccess(),
  });

  final String beaconId;
  final List<LineagePreviewRow> rows;

  LineageSuggestionsPreviewState copyWith({
    String? beaconId,
    List<LineagePreviewRow>? rows,
    StateStatus? status,
  }) =>
      LineageSuggestionsPreviewState(
        beaconId: beaconId ?? this.beaconId,
        rows: rows ?? this.rows,
        status: status ?? this.status,
      );
}
