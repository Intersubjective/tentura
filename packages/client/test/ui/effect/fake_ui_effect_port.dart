import 'dart:async';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

class FakeUiEffectPort implements UiEffectPort {
  FakeUiEffectPort();

  final _controller = StreamController<UiEffect>.broadcast();
  final emitted = <UiEffect>[];

  @override
  Stream<UiEffect> get effects => _controller.stream;

  @override
  void emit(UiEffect effect) {
    emitted.add(effect);
    if (!_controller.isClosed) {
      _controller.add(effect);
    }
  }

  void clear() => emitted.clear();
}
