import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/app/router/root_router.dart';

import 'ui_effect.dart';
import 'ui_effect_bus.dart';
import 'ui_effect_dispatcher.dart';

/// Root-level adapter: subscribes to [UiEffectBus] and executes side effects once.
class UiEffectHandler extends StatefulWidget {
  const UiEffectHandler({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<UiEffectHandler> createState() => _UiEffectHandlerState();
}

class _UiEffectHandlerState extends State<UiEffectHandler> {
  StreamSubscription<UiEffect>? _subscription;

  @override
  void initState() {
    super.initState();
    final bus = GetIt.I<UiEffectBus>();
    _subscription = bus.effects.listen(_onEffect);
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
