import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/entity/beacon_lobby.dart';
import '../../domain/use_case/beacon_lobby_case.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

/// Request Questions entry row: the viewer's own standing from the server
/// policy (`null` until known, and on failure: the row stays hidden).
class BeaconLobbyEntryCubit extends Cubit<BeaconLobbyAccess?> {
  BeaconLobbyEntryCubit(this._case, {required this.beaconId}) : super(null) {
    _changes =
        MergeStream<void>([
              _case.messageChanges(beaconId),
              _case.accessChanges(beaconId),
            ])
            .debounceTime(const Duration(milliseconds: 300))
            .listen((_) => unawaited(load()));
  }

  final String beaconId;

  final BeaconLobbyCase _case;

  late final StreamSubscription<void> _changes;

  Future<void> load() async {
    try {
      final access = await _case.access(beaconId);
      if (!isClosed) emit(access);
    } catch (_) {
      // Keep what is shown; the next hint retries.
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
