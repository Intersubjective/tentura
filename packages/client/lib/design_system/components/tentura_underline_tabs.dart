import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Underline tab row: full-width bottom border; active tab 2px sky underline.
class TenturaUnderlineTabs extends StatelessWidget {
  const TenturaUnderlineTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.badges,
    super.key,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<int?>? badges;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tt.border),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _TabCell(
                label: tabs[i],
                selected: i == selectedIndex,
                onTap: () => onChanged(i),
                badge: badges != null && i < badges!.length ? badges![i] : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _TabCell extends StatelessWidget {
  const _TabCell({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final active = tt.info;
    final inactive = tt.textMuted;
    final hasBadge = badge != null && badge! > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tt.rowGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  // Reserve some space so the badge doesn't overlap the label.
                  padding: EdgeInsets.only(right: hasBadge ? 14 : 0),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TenturaText.tabLabel(
                      selected ? active : inactive,
                    ),
                  ),
                ),
                if (hasBadge)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: _BadgeBubble(count: badge!),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? active : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeBubble extends StatelessWidget {
  const _BadgeBubble({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tt.info,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Center(
            child: Text(
              '$count',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.labelSmall(Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
