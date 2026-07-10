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
      (event) {
        if (event.type == 'webkitvisibilitychange') {
          //
        }
      },
    );
  }

  @override
  void dispose() {
    // dispose() must stay synchronous and end in super.dispose(); an async
    // override returns at the first await and trips the framework's
    // "failed to call super.dispose" assert when the tree is finalized.
    unawaited(_webEvents.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
