/// Rendered state of the browser-tab attention indicator.
///
/// [count] is the raw unread total (fed to the OS app badge, which caps it
/// itself); [label] is the capped, title-safe rendering. The two are deduped
/// separately — see the plan §2.2.
typedef TabAttentionDisplay = ({int count, String label});

const tabAttentionNone = (count: 0, label: '');

/// Above this the title shows `99+`.
const kTabAttentionDisplayCap = 99;

/// The whole product rule: tab chrome mirrors unread only while the tab is in
/// the background; focusing clears it (the in-app Updates badge keeps the real
/// count). See docs/plans/web-tab-unread-indicator-plan.md §2.
TabAttentionDisplay resolveTabAttentionDisplay({
  required int unreadTotal,
  required bool isBackground,
}) {
  if (!isBackground || unreadTotal <= 0) return tabAttentionNone;
  return (
    count: unreadTotal,
    label: unreadTotal > kTabAttentionDisplayCap
        ? '$kTabAttentionDisplayCap+'
        : '$unreadTotal',
  );
}

String composeTabTitle({
  required String baseTitle,
  required TabAttentionDisplay display,
}) => display.label.isEmpty ? baseTitle : '(${display.label}) $baseTitle';
