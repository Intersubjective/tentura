import 'dart:async';
import 'package:web/web.dart';
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
  late final StreamSubscription<Event> _webEvents;

  @override
  void initState() {
    super.initState();
    _webEvents = document.onVisibilityChange.listen(
      (Event event) {
        if (event.type == 'webkitvisibilitychange') {
          //
        }
      },
    );
  }

  @override
  Future<void> dispose() async {
    await _webEvents.cancel();
    return super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
