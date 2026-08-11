import 'package:tentura/design_system/tentura_tab_indicator.dart';
import 'package:tentura/ui/model/tab_attention_display.dart';

class TabAttentionIndicator {
  /// `true` while the tab/window is hidden. Never fires on native.
  Stream<bool> get backgroundChanges => const Stream<bool>.empty();

  bool get isBackground => false;

  /// Writes all web tab chrome synchronously. Never waits for a Flutter frame.
  /// [baseTitle] is the current localized title supplied while the app is visible.
  void apply(
    TabAttentionDisplay display,
    TenturaTabIndicatorStyle style, {
    required String baseTitle,
  }) {}

  void dispose() {}
}
