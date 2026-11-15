import 'dart:async';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'fact_picker_state.dart';

export 'fact_picker_state.dart';

/// Shared controller of the fact picker sheet: scope, query, saved list,
/// debounced server search and the pick (copy) outcome. Talks to
/// [BeaconThreadsCase] only.
class FactPickerCubit extends Cubit<FactPickerState> {
  FactPickerCubit({
    required BeaconThreadsCase threadsCase,
    required this.destinationBeaconId,
    required this.mode,
    this._hereFacts = const [],
  }) : _case = threadsCase,
       super(
         mode == FactPickerMode.quote
             ? const FactPickerState(
                 scopes: FactPickerScope.values,
                 scope: FactPickerScope.here,
               )
             : const FactPickerState(
                 scopes: [FactPickerScope.saved, FactPickerScope.all],
                 scope: FactPickerScope.saved,
               ),
       );

  final String destinationBeaconId;
  final FactPickerMode mode;

  static const searchDebounce = Duration(milliseconds: 300);
  static const minSearchLength = 2;

  final BeaconThreadsCase _case;
  final List<BeaconFactCard> _hereFacts;

  List<BeaconSavedFact>? _saved;
  bool _savedRequested = false;
  Timer? _debounce;

  /// Bumped whenever a pending search stops being the current one.
  int _searchEpoch = 0;

  /// Folds like the server: lower case, ё as е.
  static String fold(String s) => s.toLowerCase().replaceAll('ё', 'е');

  static bool _matches(List<String> words, String? text) {
    final folded = fold(text ?? '');
    return words.every(folded.contains);
  }

  /// Opens the initial scope (loads saved facts when it needs them).
  Future<void> start() async {
    _refresh();
    await _ensureSaved();
  }

  Future<void> setScope(FactPickerScope scope) async {
    if (!state.scopes.contains(scope)) return;
    _cancelSearch();
    emit(state.copyWith(scope: scope, results: const [], loading: false));
    _refresh();
    await _ensureSaved();
    if (scope == FactPickerScope.all) _scheduleSearch();
  }

  void setQuery(String query) {
    emit(state.copyWith(query: query));
    _refresh();
    if (state.scope == FactPickerScope.all) _scheduleSearch();
  }

  Future<FactPickerBringResult> bring(String factCardId) async {
    try {
      final r = await _case.copyFact(
        sourceFactCardId: factCardId,
        destinationBeaconId: destinationBeaconId,
      );
      return FactPickerBringResult.copied(r.outcome);
    } on Object catch (e) {
      if (e is BeaconFactCopySourceUnavailableException && !isClosed) {
        emit(
          state.copyWith(unavailableIds: {...state.unavailableIds, factCardId}),
        );
      }
      return FactPickerBringResult.failed(e);
    }
  }

  Future<void> unsave(String factCardId) async {
    await _case.unsaveFact(factCardId: factCardId);
    _saved = _saved?.where((r) => r.factCardId != factCardId).toList();
    if (!isClosed) _refresh();
  }

  @override
  Future<void> close() {
    _cancelSearch();
    return super.close();
  }

  Future<void> _ensureSaved() async {
    if (state.scope != FactPickerScope.saved || _savedRequested) return;
    _savedRequested = true;
    try {
      _saved = await _case.savedFacts();
      if (!isClosed) emit(state.copyWith(savedFailed: false));
    } on Object {
      if (!isClosed) emit(state.copyWith(savedFailed: true));
    }
    if (!isClosed) _refresh();
  }

  /// Recomputes the locally filtered rows and the hint.
  void _refresh() {
    final words = fold(state.query).split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final saved = (_saved ?? const <BeaconSavedFact>[]).where(
      (r) =>
          (mode == FactPickerMode.quote || r.beaconId != destinationBeaconId) &&
          _matches(words, r.factText),
    );
    emit(
      state.copyWith(
        hereRows: _hereFacts.where((f) => _matches(words, f.factText)).toList(),
        savedRows: saved.toList(),
        showHint:
            state.scope == FactPickerScope.all && !_isSearchable(state.query),
      ),
    );
  }

  bool _isSearchable(String query) =>
      fold(query).trim().length >= minSearchLength;

  void _cancelSearch() {
    _debounce?.cancel();
    _debounce = null;
    _searchEpoch++;
  }

  void _scheduleSearch() {
    _cancelSearch();
    if (!_isSearchable(state.query)) {
      emit(state.copyWith(results: const [], loading: false, failed: false));
      return;
    }
    final epoch = _searchEpoch;
    _debounce = Timer(searchDebounce, () => unawaited(_search(epoch)));
  }

  Future<void> _search(int epoch) async {
    final query = state.query.trim();
    emit(state.copyWith(loading: true, failed: false));
    try {
      final hits = await _case.searchAvailableFacts(
        query: query,
        excludeBeaconId: destinationBeaconId,
      );
      if (isClosed || epoch != _searchEpoch) return;
      emit(state.copyWith(results: hits, loading: false));
    } on Object {
      if (isClosed || epoch != _searchEpoch) return;
      emit(state.copyWith(results: const [], loading: false, failed: true));
    }
  }
}
