import 'dart:async';

import 'package:injectable/injectable.dart';

import 'ui_effect.dart';
import 'ui_effect_port.dart';

@Singleton(as: UiEffectPort)
class UiEffectBus implements UiEffectPort {
  UiEffectBus();

  final _controller = StreamController<UiEffect>.broadcast();

  @override
  Stream<UiEffect> get effects => _controller.stream;

  @override
  void emit(UiEffect effect) {
    if (!_controller.isClosed) {
      _controller.add(effect);
    }
  }
}
