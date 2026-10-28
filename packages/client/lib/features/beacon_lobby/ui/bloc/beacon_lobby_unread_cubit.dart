import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

/// How many of this Request's Questions notices the author has not settled
/// yet (#656). Re-read whenever the attention feed moves (a settle, a clear, a new
/// notice all refresh the feed head).
class BeaconLobbyUnreadCubit extends Cubit<int> {
  BeaconLobbyUnreadCubit(this._attention, {required this.beaconId}) : super(0) {
    _changes = _attention.feedPages.listen((_) => unawaited(_read()));
  }

  final String beaconId;

  final AttentionCase _attention;

  late final StreamSubscription<void> _changes;

  /// Bumped by every read; only the newest read may emit.
  int _seq = 0;

  Future<void> _read() async {
    final seq = ++_seq;
    try {
      final page = await _attention.activityAttention(beaconId: beaconId);
      if (isClosed || seq != _seq) return;
      emit(
        page.events
            .where(
              (r) =>
                  isQuestionsAttentionReceipt(r) &&
                  r.settledAt == null &&
                  !r.isCleared,
            )
            .length,
      );
    } catch (_) {
      // Keep what is shown until the next change.
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
