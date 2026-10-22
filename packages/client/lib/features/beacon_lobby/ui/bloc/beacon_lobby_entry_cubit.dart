import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/use_case/beacon_lobby_case.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

/// Request Questions entry row: the viewer's own standing from the server
/// policy (`null` until known, and on failure: the row stays hidden).
///
/// Re-read on message / standing hints, when the Request page says the
/// viewer's standing changed ([load] from the row, #655), and — after a
/// failed read — a few times with backoff, so one dropped request does not
/// hide the row for the life of the page.
class BeaconLobbyEntryCubit extends Cubit<BeaconLobbyAccess?> {
  BeaconLobbyEntryCubit(
    this._case, {
    required this.beaconId,
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 6),
      Duration(seconds: 20),
    ],
  }) : super(null) {
    _changes =
        MergeStream<void>([
              _case.messageChanges(beaconId),
              _case.accessChanges(beaconId),
            ])
            .debounceTime(const Duration(milliseconds: 300))
            .listen((_) => unawaited(load()));
  }

  final String beaconId;

  /// Waits before each retry of a failed read.
  final List<Duration> retryDelays;

  final BeaconLobbyCase _case;

  late final StreamSubscription<void> _changes;

  Timer? _retry;

  int _failures = 0;

  /// Bumped by every read; only the newest read may emit.
  int _seq = 0;

  /// Reads the standing again, with a fresh retry budget.
  Future<void> load() {
    _failures = 0;
    return _read();
  }

  Future<void> _read() async {
    _retry?.cancel();
    final seq = ++_seq;
    try {
      final access = await _case.access(beaconId);
      if (isClosed || seq != _seq) return;
      emit(access);
    } catch (_) {
      // Keep what is shown; retry a few times, then wait for the next hint.
      if (isClosed || seq != _seq || _failures >= retryDelays.length) return;
      _retry = Timer(retryDelays[_failures++], () => unawaited(_read()));
    }
  }

  @override
  Future<void> close() async {
    _retry?.cancel();
    await _changes.cancel();
    return super.close();
  }
}
