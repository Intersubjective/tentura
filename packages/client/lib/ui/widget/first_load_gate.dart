import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

/// Gates initial screen content until it is ready, fails, or times out.
class TenturaFirstLoadGate extends StatefulWidget {
  const TenturaFirstLoadGate({
    required this.ready,
    required this.child,
    required this.onRetry,
    this.error,
    this.onSignInAgain,
    super.key,
  });

  final bool ready;
  final Widget child;
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback? onSignInAgain;

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
    if (_hasBeenReady) return widget.child;
    final error = widget.error;
    if (error != null) {
      return ScreenLoadErrorPanel(
        details: describeScreenLoadError(
          error: error,
          l10n: L10n.of(context)!,
        ),
        onRetry: widget.onRetry,
        onSignInAgain: widget.onSignInAgain,
      );
    }
    if (_timedOut) return widget.child;
    if (_showSpinner) {
      return const Center(child: CircularProgressIndicator());
    }
    return const SizedBox.shrink();
  }
}
