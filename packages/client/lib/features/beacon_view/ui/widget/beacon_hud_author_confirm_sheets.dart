import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

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
              Semantics(
                identifier: TestIds.beaconHudMarkEnoughHelpConfirm,
                button: true,
                child: FilledButton(
                  key: TestIds.key(TestIds.beaconHudMarkEnoughHelpConfirm),
                  onPressed: () {
                    confirmed = true;
                    Navigator.of(ctx).pop();
                  },
                  child: Text(l10n.beaconHudConfirmMarkEnoughHelpAction),
                ),
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

/// Shared close-now confirm for every author close entry (HUD, status sheet,
/// My Work). [unsentStartedPackages] is the beacon-scoped count of packages
/// started and not sent; they are discarded on close.
Future<bool> showBeaconCloseNowConfirmSheet({
  required BuildContext context,
  bool canCloseNow = true,
  int unsentStartedPackages = 0,
}) {
  final l10n = L10n.of(context)!;
  return _showAuthorConfirmSheet(
    context: context,
    title: l10n.beaconHudConfirmCloseNowTitle,
    body: [
      if (canCloseNow) ...[
        l10n.beaconReviewCloseNowBody,
        if (unsentStartedPackages > 0)
          l10n.beaconReviewCloseNowDiscardNote(unsentStartedPackages),
      ] else
        l10n.beaconHudConfirmCloseNowBlockedBody,
    ],
    action: l10n.beaconHudConfirmCloseNowAction,
    actionId: TestIds.beaconCloseNowConfirm,
    enabled: canCloseNow,
  );
}

/// Shared reopen confirm; names reviewers whose send is undone.
Future<bool> showBeaconReopenConfirmSheet({
  required BuildContext context,
  required int sentReviewerCount,
}) {
  final l10n = L10n.of(context)!;
  return _showAuthorConfirmSheet(
    context: context,
    title: l10n.beaconReviewReopenTitle,
    body: [
      if (sentReviewerCount > 0)
        l10n.beaconReviewReopenBody(sentReviewerCount)
      else
        l10n.beaconReviewReopenBodyNoSent,
    ],
    action: l10n.beaconReviewReopenConfirm,
  );
}

Future<bool> _showAuthorConfirmSheet({
  required BuildContext context,
  required String title,
  required List<String> body,
  required String action,
  String? actionId,
  bool enabled = true,
}) async {
  final l10n = L10n.of(context)!;
  var confirmed = false;
  await showTenturaAdaptiveSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final tt = ctx.tt;
      final bodyStyle = TenturaText.body(Theme.of(ctx).colorScheme.onSurface);
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
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              for (final paragraph in body) ...[
                SizedBox(height: tt.rowGap),
                Text(paragraph, style: bodyStyle),
              ],
              SizedBox(height: tt.sectionGap),
              Semantics(
                identifier: actionId,
                child: FilledButton(
                  key: actionId == null ? null : TestIds.key(actionId),
                  onPressed: enabled
                      ? () {
                          confirmed = true;
                          Navigator.of(ctx).pop();
                        }
                      : null,
                  child: Text(action),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.buttonCancel),
              ),
            ],
          ),
        ),
      );
    },
  );
  return confirmed;
}
