import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'attention_case.dart';

/// Clears the optional attention a Request accumulated, because it was opened
/// (§4, "Opening the Request").
typedef RequestOpenClear = Future<void> Function({required String beaconId});

Future<void> _clearViaGetIt({required String beaconId}) =>
    GetIt.I<AttentionCase>().clearRequestOpen(beaconId: beaconId);

/// One open, one clear.
///
/// §4 binds three things at once and this gate holds all three:
///
/// - the clear happens **after** the Request successfully displays, so a
///   forbidden, failed or cancelled open clears nothing — callers must only
///   call [reportDisplayed] once they have actually shown it;
/// - the snapshot is captured at apply time, so events arriving while the
///   person reads survive — that is [AttentionCase.clearRequestOpen]'s
///   contract, not this gate's;
/// - clearing is a deliberate gesture, so a **background refresh** that
///   re-reports the same successful display must not clear a second time.
///   That is what the once-per-instance latch below is for: it is the guard,
///   not a belt over a listener-level brace.
class RequestOpenClearGate {
  RequestOpenClearGate({RequestOpenClear? clear})
    : _clear = clear ?? _clearViaGetIt;

  static final _logger = Logger('RequestOpenClearGate');

  final RequestOpenClear _clear;

  bool _fired = false;

  /// True once this visit has spent its single clear.
  bool get hasCleared => _fired;

  /// Reports that [beaconId] is now on screen. Clears once per instance.
  Future<void> reportDisplayed(String beaconId) async {
    if (_fired || beaconId.isEmpty) return;
    _fired = true;
    try {
      await _clear(beaconId: beaconId);
    } on Object catch (error, stackTrace) {
      // A failed clear is not a failed open: the Request is already on
      // screen. Surfacing it would be noise, and retrying it on the next
      // frame would turn a rebuild into a gesture.
      _logger.warning('Request-open clear failed', error, stackTrace);
    }
  }
}
