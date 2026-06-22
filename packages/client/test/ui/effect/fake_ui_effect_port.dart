import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

class FakeUiEffectPort implements UiEffectPort {
  FakeUiEffectPort();

  final emitted = <UiEffect>[];

  @override
  void emit(UiEffect effect) => emitted.add(effect);

  void clear() => emitted.clear();
}
