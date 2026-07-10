import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Lightweight confirm before marking enough help from the author HUD.
Future<bool> showBeaconHudMarkEnoughHelpConfirmSheet({
  required BuildContext context,
}) async {
  final l10n = L10n.of(context)!;
  var confirmed = false;
  await showTenturaAdaptiveSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final tt = ctx.tt;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.rowGap,
            tt.screenHPadding,
            tt.sectionGap + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.beaconHudConfirmMarkEnoughHelpTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              SizedBox(height: tt.rowGap),
              Text(
                l10n.beaconHudConfirmMarkEnoughHelpBody,
                style: TenturaText.body(Theme.of(ctx).colorScheme.onSurface),
              ),
              SizedBox(height: tt.sectionGap),
              FilledButton(
                onPressed: () {
                  confirmed = true;
                  Navigator.of(ctx).pop();
                },
                child: Text(l10n.beaconHudConfirmMarkEnoughHelpAction),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.buttonCancel),
              ),
              SizedBox(height: tt.tightGap),
              Text(
                l10n.beaconHudConfirmChangeLaterInStatus,
                style: TenturaText.bodySmall(tt.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    },
  );
  return confirmed;
}

/// Confirm before closing a request immediately from the author HUD.
Future<bool> showBeaconHudCloseNowConfirmSheet({
  required BuildContext context,
  required bool canCloseNow,
}) async {
  final l10n = L10n.of(context)!;
  var confirmed = false;
  await showTenturaAdaptiveSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final tt = ctx.tt;
      final body = canCloseNow
          ? l10n.beaconHudConfirmCloseNowBody
          : l10n.beaconHudConfirmCloseNowBlockedBody;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.rowGap,
            tt.screenHPadding,
            tt.sectionGap + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.beaconHudConfirmCloseNowTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              SizedBox(height: tt.rowGap),
              Text(
                body,
                style: TenturaText.body(Theme.of(ctx).colorScheme.onSurface),
              ),
              SizedBox(height: tt.sectionGap),
              FilledButton(
                onPressed: canCloseNow
                    ? () {
                        confirmed = true;
                        Navigator.of(ctx).pop();
                      }
                    : null,
                child: Text(l10n.beaconHudConfirmCloseNowAction),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.buttonCancel),
              ),
              if (canCloseNow) ...[
                SizedBox(height: tt.tightGap),
                Text(
                  l10n.beaconHudConfirmChangeLaterInStatus,
                  style: TenturaText.bodySmall(tt.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  return confirmed;
}
