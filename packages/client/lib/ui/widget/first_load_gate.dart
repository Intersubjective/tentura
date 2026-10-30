import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

/// Gates initial screen content until it is ready, fails, or optionally times out.
class TenturaFirstLoadGate extends StatefulWidget {
  const TenturaFirstLoadGate({
    required this.ready,
    required this.child,
    required this.onRetry,
    this.error,
    this.onSignInAgain,
    this.revealOnTimeout = true,
    super.key,
  });

  final bool ready;
  final Widget child;
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback? onSignInAgain;

  /// Disable when revealing partial content would expose unfinished sections.
  final bool revealOnTimeout;

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
    return Stack(
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
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
