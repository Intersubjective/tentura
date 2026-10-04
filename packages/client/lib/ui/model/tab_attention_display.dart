/// Rendered state of the browser-tab attention indicator.
///
/// [count] is the raw unread total (fed to the OS app badge, which caps it
/// itself); [label] is the capped, title-safe rendering. The two are deduped
/// separately — see the plan §2.2.
typedef TabAttentionDisplay = ({int count, String label});

const tabAttentionNone = (count: 0, label: '');

/// Above this the title shows `99+`.
const kTabAttentionDisplayCap = 99;

/// Tab chrome mirrors the real unread count regardless of focus: the
/// indicator no longer clears just because the tab became active — only the
/// unread count itself clearing does that. Supersedes the background-gating
/// rule in docs/plans/web-tab-unread-indicator-plan.md §2.
TabAttentionDisplay resolveTabAttentionDisplay({required int unreadTotal}) {
  if (unreadTotal <= 0) return tabAttentionNone;
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
