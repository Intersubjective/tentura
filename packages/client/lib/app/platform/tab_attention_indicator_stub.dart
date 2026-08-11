import 'package:tentura/design_system/tentura_tab_indicator.dart';
import 'package:tentura/ui/model/tab_attention_display.dart';

class TabAttentionIndicator {
  /// `true` while the tab/window is hidden. Never fires on native.
  Stream<bool> get backgroundChanges => const Stream<bool>.empty();

  bool get isBackground => false;

  /// Writes selected web tab chrome channels synchronously.
  /// Never waits for a Flutter frame.
  /// [baseTitle] is the current localized title supplied while the app is visible.
  /// Named channel flags let callers update title, favicon, and badge independently.
  void apply(
    TabAttentionDisplay display,
    TenturaTabIndicatorStyle style, {
    required String baseTitle,
    bool applyTitle = true,
    bool applyFavicon = true,
    bool applyBadge = true,
  }) {}

  void dispose() {}
}
