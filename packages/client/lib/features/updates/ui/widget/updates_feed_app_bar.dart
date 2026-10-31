import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Compact Updates app-bar contents: title + Read all + search icon.
class UpdatesFeedAppBarRow extends StatelessWidget {
  const UpdatesFeedAppBarRow({
    required this.title,
    required this.markAllLabel,
    required this.hasUnread,
    required this.onMarkAll,
    required this.showSearchIcon,
    required this.searchOpen,
    required this.onSearchPressed,
    required this.searchTooltip,
    super.key,
  });

  final String title;
  final String markAllLabel;
  final bool hasUnread;
  final VoidCallback onMarkAll;
  final bool showSearchIcon;
  final bool searchOpen;
  final VoidCallback onSearchPressed;
  final String searchTooltip;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    // #258: a text button at every width; an icon-only ✓✓ on phones is
    // why nobody found it. Disabled, not hidden, so the bar does not shift.
    final markAllControl = TenturaTextAction(
      label: markAllLabel,
      onPressed: hasUnread ? onMarkAll : null,
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TenturaText.titleLarge(tt.text),
          ),
        ),
        markAllControl,
        if (showSearchIcon)
          IconButton(
            tooltip: searchTooltip,
            isSelected: searchOpen,
            onPressed: onSearchPressed,
            icon: const Icon(Icons.search),
          ),
      ],
    );
  }
}
