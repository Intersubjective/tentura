import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_progress.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

/// Gates initial screen content until it is ready, fails, or optionally times out.
///
/// **Screen contract:** each screen cubit exposes a `firstLoadDone` flag that
/// turns true once primary slices have arrived and **never goes back** —
/// background refreshes update in place and must not re-open this gate. While
/// `ready` is false, the gate shows `TenturaCircularProgress` only after 150 ms
/// and `ScreenLoadErrorPanel` on a first-load error.
///
/// By default the gate does **not** reveal over unfinished primary data. Opt in
/// with `revealOnTimeout: true` only when a **secondary** read may still be
/// in flight after the primary slices are ready (for example Request child reads).
class TenturaFirstLoadGate extends StatefulWidget {
  const TenturaFirstLoadGate({
    required this.ready,
    required this.child,
    required this.onRetry,
    this.error,
    this.onSignInAgain,
    this.revealOnTimeout = false,
    this.frameBuilder,
    this.progress,
    super.key,
  });

  final bool ready;
  final Widget child;
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback? onSignInAgain;

  /// Disable when revealing partial content would expose unfinished sections.
  final bool revealOnTimeout;

  /// Builds a frame around the gated stack in the same build that decides
  /// whether the gate has revealed. Chrome outside the body (a top-bar status)
  /// uses that flag instead of a second copy of [ready] / [revealOnTimeout].
  /// Omit it and the gate itself is the stack. The stack argument is the
  /// hidden child plus the spinner or error; put it in the body so the bar
  /// stays up while the gate is closed.
  final Widget Function(BuildContext context, bool revealed, Widget gated)?
  frameBuilder;

  /// Optional step label and determinate progress while the gate is closed.
  final FirstLoadProgress? progress;

  @override
  State<TenturaFirstLoadGate> createState() => _TenturaFirstLoadGateState();
}

class _TenturaFirstLoadGateState extends State<TenturaFirstLoadGate> {
  Timer? _spinnerTimer;
  Timer? _timeoutTimer;
  bool _hasBeenReady = false;
  bool _showSpinner = false;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _hasBeenReady = widget.ready;
    if (_hasBeenReady) return;
    _spinnerTimer = Timer(const Duration(milliseconds: 150), () {
      setState(() => _showSpinner = true);
    });
    _timeoutTimer = Timer(const Duration(milliseconds: 2500), () {
      setState(() => _timedOut = true);
    });
  }

  @override
  void didUpdateWidget(covariant TenturaFirstLoadGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready) {
      _hasBeenReady = true;
      _cancelTimers();
    }
  }

  void _cancelTimers() {
    _spinnerTimer?.cancel();
    _timeoutTimer?.cancel();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _hasBeenReady ? null : widget.error;
    final revealed =
        _hasBeenReady || (widget.revealOnTimeout && error == null && _timedOut);
    // The child stays mounted while hidden, so its own loads (e.g. a Request
    // room) start behind the gate and revealing it keeps its state.
    final gated = Stack(
      fit: StackFit.passthrough,
      children: [
        Visibility(
          visible: revealed,
          maintainState: true,
          child: widget.child,
        ),
        if (error != null)
          ScreenLoadErrorPanel(
            details: describeScreenLoadError(
              error: error,
              l10n: L10n.of(context)!,
            ),
            onRetry: widget.onRetry,
            onSignInAgain: widget.onSignInAgain,
          )
        else if (!revealed && _showSpinner)
          if (widget.progress != null)
            FirstLoadStatusPanel(progress: widget.progress)
          else
            const Center(child: TenturaCircularProgress()),
      ],
    );
    final frame = widget.frameBuilder;
    if (frame == null) return gated;
    return frame(context, revealed, gated);
  }
}
