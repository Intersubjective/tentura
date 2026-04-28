import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Minimal top bar: close, title + subtitle, optional search & filter actions.
class ForwardTopBar extends StatelessWidget {
  const ForwardTopBar({
    required this.titleLine,
    required this.subtitleLine,
    this.closeFallbackPath,
    this.onSearchPressed,
    this.onFilterPressed,
    this.searchTooltip,
    this.filterTooltip,
    super.key,
  });

  final String titleLine;
  final String subtitleLine;

  /// When the route stack cannot pop (e.g. web refresh), navigate here on close.
  final String? closeFallbackPath;
  final VoidCallback? onSearchPressed;
  final VoidCallback? onFilterPressed;
  final String? searchTooltip;
  final String? filterTooltip;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.only(
        left: tt.iconTextGap,
        right: tt.screenHPadding,
      ),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(Icons.close, size: tt.iconSize, color: tt.text),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () {
              final router = context.router;
              if (router.canPop()) {
                unawaited(router.maybePop());
              } else if (closeFallbackPath != null) {
                unawaited(router.navigatePath(closeFallbackPath!));
              }
            },
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.title(tt.text),
                ),
                Text(
                  subtitleLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ],
            ),
          ),
          if (onSearchPressed != null)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(Icons.search, size: tt.iconSize, color: tt.text),
              tooltip: searchTooltip,
              onPressed: onSearchPressed,
            ),
          if (onFilterPressed != null)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(Icons.tune, size: tt.iconSize, color: tt.text),
              tooltip: filterTooltip,
              onPressed: onFilterPressed,
            ),
        ],
      ),
    );
  }
}

String forwardBeaconSubtitle({
  required L10n l10n,
  required String beaconTitle,
  required String lifecycleLabel,
}) {
  if (beaconTitle.isEmpty) {
    return lifecycleLabel;
  }
  return '$beaconTitle · $lifecycleLabel';
}
