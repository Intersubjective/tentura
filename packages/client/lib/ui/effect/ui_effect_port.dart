import 'ui_effect.dart';

/// Presentation-layer port for one-shot UI side effects (snackbar, nav, error).
abstract interface class UiEffectPort {
  Stream<UiEffect> get effects;

  void emit(UiEffect effect);
}
