import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/ui/bloc/state_base.dart';

/// Quote: the destination's own facts are pickable too. Bring: only facts
/// from elsewhere are copied into the destination.
enum FactPickerMode { quote, bring }

enum FactPickerScope { here, saved, all }

/// What `FactPickerCubit.bring` reports: exactly one of [copyOutcome]
/// (copied) and [error] (failed) is set.
class FactPickerBringResult {
  const FactPickerBringResult.copied(BeaconFactCopyOutcome this.copyOutcome)
    : error = null;

  const FactPickerBringResult.failed(Object this.error) : copyOutcome = null;

  final BeaconFactCopyOutcome? copyOutcome;
  final Object? error;

  bool get isUnavailable => error is BeaconFactCopySourceUnavailableException;
}

class FactPickerState extends StateBase {
  const FactPickerState({
    required this.scopes,
    required this.scope,
    this.query = '',
    this.hereRows = const [],
    this.savedRows = const [],
    this.results = const [],
    this.loading = false,
    this.failed = false,
    this.savedFailed = false,
    this.showHint = false,
    this.unavailableIds = const {},
  });

  final List<FactPickerScope> scopes;
  final FactPickerScope scope;
  final String query;

  /// Rows of the active scopes, already filtered by [query] (here, saved) or
  /// as returned by the server (results).
  final List<BeaconFactCard> hereRows;
  final List<BeaconSavedFact> savedRows;
  final List<BeaconFactSearchHit> results;

  /// A server search is in flight.
  final bool loading;
  final bool failed;
  final bool savedFailed;

  /// The All scope waits for a longer query; no search was made.
  final bool showHint;

  /// Rows whose source can no longer be copied.
  final Set<String> unavailableIds;

  FactPickerState copyWith({
    FactPickerScope? scope,
    String? query,
    List<BeaconFactCard>? hereRows,
    List<BeaconSavedFact>? savedRows,
    List<BeaconFactSearchHit>? results,
    bool? loading,
    bool? failed,
    bool? savedFailed,
    bool? showHint,
    Set<String>? unavailableIds,
  }) => FactPickerState(
    scopes: scopes,
    scope: scope ?? this.scope,
    query: query ?? this.query,
    hereRows: hereRows ?? this.hereRows,
    savedRows: savedRows ?? this.savedRows,
    results: results ?? this.results,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    savedFailed: savedFailed ?? this.savedFailed,
    showHint: showHint ?? this.showHint,
    unavailableIds: unavailableIds ?? this.unavailableIds,
  );
}
