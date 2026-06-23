import 'dart:async';

import 'package:flutter/material.dart';

import 'ui_effect.dart';
import 'ui_effect_dispatcher.dart';
import 'ui_effect_port.dart';

/// Root-level adapter: subscribes to [UiEffectPort] and executes side effects once.
class UiEffectHandler extends StatefulWidget {
  const UiEffectHandler({
    required this.child,
    required this.effects,
    super.key,
  });

  final Widget child;
  final UiEffectPort effects;

  @override
  State<UiEffectHandler> createState() => _UiEffectHandlerState();
}

class _UiEffectHandlerState extends State<UiEffectHandler> {
  StreamSubscription<UiEffect>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.effects.effects.listen(_onEffect);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onEffect(UiEffect effect) {
    if (!mounted) return;
    dispatchUiEffect(context, effect);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
