import 'ui_effect.dart';

/// Presentation-layer port for one-shot UI side effects (snackbar, nav, error).
abstract interface class UiEffectPort {
  void emit(UiEffect effect);
}
