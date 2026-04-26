import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Underline tab row: full-width bottom border; active tab 2px sky underline.
class TenturaUnderlineTabs extends StatelessWidget {
  const TenturaUnderlineTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final active = tt.info;
    final inactive = tt.textMuted;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TenturaText.tabLabel(
                selected ? active : inactive,
              ),
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
