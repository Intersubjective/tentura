import 'dart:async';

import 'package:flutter/material.dart';

/// Indeterminate top-bar progress that respects reduced motion.
///
/// [AnimationController.repeat] prevents [WidgetTester.pumpAndSettle] from
/// ever completing while this widget is mounted. When
/// [MediaQuery.disableAnimationsOf] is true (integration tests / OS reduce
/// motion), render a static mid-progress bar instead.
class LinearPiActive extends StatefulWidget {
  static const height = 4.0;

  static const size = Size.fromHeight(height);

  static Widget builder(
    BuildContext context,
    bool isLoading, {
    Color? color,
    Color? backgroundColor,
  }) => isLoading
      ? LinearPiActive(
          color: color,
          backgroundColor: backgroundColor,
        )
      : const SizedBox(height: height);

  const LinearPiActive({
    this._duration = const Duration(seconds: 2),
    this.color,
    this.backgroundColor,
    super.key,
  });

  final Duration _duration;
  final Color? color;
  final Color? backgroundColor;

  @override
  State<LinearPiActive> createState() => _LinearPiActiveState();
}

class _LinearPiActiveState extends State<LinearPiActive>
    with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget._duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.5;
      return;
    }
    if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
    value: _controller.value,
    color: widget.color,
    backgroundColor: widget.backgroundColor,
  );
}
