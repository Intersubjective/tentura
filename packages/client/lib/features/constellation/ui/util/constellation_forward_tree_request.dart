import 'package:flutter/foundation.dart';

/// One-shot request to open the Field in forward-tree mode (#774 31ve.6).
final class ConstellationForwardTreeRequest {
  ConstellationForwardTreeRequest._();

  static final instance = ConstellationForwardTreeRequest._();

  final _pending = ValueNotifier<ConstellationForwardTreeRequestPayload?>(null);

  ValueListenable<ConstellationForwardTreeRequestPayload?> get pending =>
      _pending;

  ConstellationForwardTreeRequestPayload? get pendingPayload =>
      _pending.value;

  set pendingPayload(ConstellationForwardTreeRequestPayload payload) {
    _pending.value = payload;
  }

  ConstellationForwardTreeRequestPayload? take() {
    final v = _pending.value;
    _pending.value = null;
    return v;
  }
}

/// Parameters for [ConstellationForwardTreeRequest.pendingPayload].
@immutable
final class ConstellationForwardTreeRequestPayload {
  const ConstellationForwardTreeRequestPayload({
    required this.beaconId,
    this.helpOffererId,
  });

  final String beaconId;

  /// When set, edges on paths to this help offerer use the thick help-path style
  /// (`ConstellationEdgeKind.helpBranch` on the scene).
  final String? helpOffererId;
}
