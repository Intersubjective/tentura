import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:tentura/domain/attention/seen_ack_case.dart';

/// Converts Flutter visibility/lifecycle signals into the domain dwell rule.
class AttentionVisibilityAck extends StatefulWidget {
  const AttentionVisibilityAck({
    required this.receiptId,
    required this.isSeen,
    required this.onAcknowledge,
    required this.child,
    super.key,
  });

  final String receiptId;
  final bool isSeen;
  final Future<void> Function(String id) onAcknowledge;
  final Widget child;

  @override
  State<AttentionVisibilityAck> createState() => _AttentionVisibilityAckState();
}

class _AttentionVisibilityAckState extends State<AttentionVisibilityAck>
    with WidgetsBindingObserver {
  static const _case = SeenAckCase();
  DateTime? _visibleSince;
  double _visibleFraction = 0;
  bool _focused = true;
  bool _acknowledging = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _focused = state == AppLifecycleState.resumed;
    if (!_focused) _reset();
  }

  void _onVisibility(VisibilityInfo info) {
    _visibleFraction = info.visibleFraction;
    if (_visibleFraction < _case.minimumVisibleFraction || !_focused) {
      _reset();
      return;
    }
    _visibleSince ??= DateTime.now();
    _timer ??= Timer(_case.minimumDwell, _evaluate);
  }

  void _evaluate() {
    _timer = null;
    final started = _visibleSince;
    if (started == null || widget.isSeen || _acknowledging) return;
    if (!_case.shouldAcknowledge(
      AttentionVisibilityEvidence(
        visibleFraction: _visibleFraction,
        visibleFor: DateTime.now().difference(started),
        appIsFocused: _focused,
        routeIsCurrent: ModalRoute.of(context)?.isCurrent ?? false,
      ),
    )) {
      return;
    }
    _acknowledging = true;
    unawaited(
      widget.onAcknowledge(widget.receiptId).whenComplete(() {
        _acknowledging = false;
      }),
    );
  }

  void _reset() {
    _visibleSince = null;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisibilityDetector(
    key: ValueKey('attention-visibility-${widget.receiptId}'),
    onVisibilityChanged: _onVisibility,
    child: widget.child,
  );
}
