import 'package:flutter/material.dart';

class LinearPiActive extends StatefulWidget {
  static const height = 4.0;

  static const size = Size.fromHeight(height);

  static Widget builder(BuildContext context, bool isLoading) =>
      isLoading ? const LinearPiActive() : const SizedBox(height: height);

  const LinearPiActive({
    Duration duration = const Duration(seconds: 2),
    super.key,
  }) : _duration = duration;

  final Duration _duration;

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
    _controller
      ..addListener(() => setState(() {}))
      // ignore: discarded_futures //
      ..repeat();
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LinearProgressIndicator(value: _controller.value);
}
