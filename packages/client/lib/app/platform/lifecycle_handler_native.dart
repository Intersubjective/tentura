import 'package:flutter/widgets.dart';

class LifecycleHandler extends StatefulWidget {
  const LifecycleHandler({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends State<LifecycleHandler> {
  final _appLifecycleListener = AppLifecycleListener();

  @override
  void initState() {
    super.initState();
    _appLifecycleListener.hashCode;
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
