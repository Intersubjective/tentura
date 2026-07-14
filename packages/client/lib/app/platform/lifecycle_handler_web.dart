import 'dart:async';
import 'package:web/web.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

class LifecycleHandler extends StatefulWidget {
  const LifecycleHandler({
    required this.child,
    this.attachNotificationRouting = true,
    super.key,
  });

  final Widget child;
  final bool attachNotificationRouting;

  @override
  State<LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends State<LifecycleHandler> {
  late final StreamSubscription<Event> _webEvents;

  @override
  void initState() {
    super.initState();
    _webEvents = document.onVisibilityChange.listen(
      (_) {
        if (document.visibilityState != 'visible') return;
        GetIt.I<RealtimeSyncCase>().requestCatchUp(
          RealtimeCatchUpReason.webVisibilityRestored,
        );
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
