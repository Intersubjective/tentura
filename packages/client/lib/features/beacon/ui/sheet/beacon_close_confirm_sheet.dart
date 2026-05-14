import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Author close confirmation: copy and actions depend on [BeaconClosureReadiness].
Future<void> showBeaconCloseConfirmSheet({
  required BuildContext context,
  required BeaconClosureConfirmationSummary summary,
  required bool isLoading,
  required VoidCallback onCloseBeacon,
  required VoidCallback onOpenPeople,
  required VoidCallback onPostUpdate,
  VoidCallback? onResolveRoom,
}) async {
  final l10n = L10n.of(context)!;
  final scheme = Theme.of(context).colorScheme;
  final r = summary.readiness;

  final (title, body) = switch (r) {
    BeaconClosureReadiness.readyToClose => (
        l10n.beaconCloseSheetReadyTitle,
        l10n.beaconCloseSheetReadyBody,
      ),
    BeaconClosureReadiness.waitingForReview => (
        l10n.beaconCloseSheetReviewTitle,
        l10n.beaconCloseSheetReviewBody,
      ),
    BeaconClosureReadiness.premature => (
        l10n.beaconCloseSheetPrematureTitle,
        l10n.beaconCloseSheetPrematureBody,
      ),
    BeaconClosureReadiness.blocked => (
        l10n.beaconCloseSheetBlockedTitle,
        l10n.beaconCloseSheetBlockedBody,
      ),
    BeaconClosureReadiness.notCloseable => (
        l10n.beaconCloseSheetPrematureTitle,
        l10n.beaconCloseSheetPrematureBody,
      ),
  };

  final evidence = <Widget>[
    _evidenceRow(
      scheme,
      summary.hasOpenBlocker
          ? l10n.beaconCloseSheetEvidenceOpenBlocker
          : l10n.beaconCloseSheetEvidenceNoOpenBlocker,
      positive: !summary.hasOpenBlocker,
    ),
    if (summary.hasWholeBeaconDoneSignal)
      _evidenceRow(scheme, l10n.beaconCloseSheetEvidenceWholeBeaconDone),
    if (summary.enoughHelpOffered)
      _evidenceRow(scheme, l10n.beaconCloseSheetEvidenceEnoughHelp),
    if (summary.hasSuccessfulHelpOfferResult)
      _evidenceRow(scheme, l10n.beaconCloseSheetEvidenceUsefulOrDone),
    if (summary.unsettledRelevantCount > 0)
      _evidenceRow(
        scheme,
        l10n.beaconCloseSheetEvidenceUnsettledCount(
          summary.unsettledRelevantCount,
        ),
        positive: false,
      ),
    if (summary.unansweredHelpOffersCount > 0)
      _evidenceRow(
        scheme,
        l10n.beaconCloseSheetEvidenceUnansweredCount(
          summary.unansweredHelpOffersCount,
        ),
        positive: false,
      ),
  ];

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            16 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TenturaText.titleSmall(scheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: TenturaText.body(scheme.onSurfaceVariant),
              ),
              if (evidence.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...evidence,
              ],
              if (r == BeaconClosureReadiness.blocked &&
                  !kBeaconAllowForceCloseWhenBlocked) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.beaconCloseSheetBlockedForceHint,
                  style: TenturaText.status(scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 16),
              if (isLoading)
                const Center(child: CircularProgressIndicator.adaptive())
              else ...[
                if (r == BeaconClosureReadiness.readyToClose) ...[
                  FilledButton(
                    onPressed: onCloseBeacon,
                    child: Text(l10n.beaconCloseSheetActionCloseBeacon),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.beaconCloseSheetActionNotNow),
                  ),
                ],
                if (r == BeaconClosureReadiness.waitingForReview) ...[
                  FilledButton(
                    onPressed: onCloseBeacon,
                    child: Text(l10n.beaconCloseSheetActionCloseAnyway),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onOpenPeople();
                    },
                    child: Text(l10n.beaconCloseSheetActionOpenPeople),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.beaconCloseSheetActionNotNow),
                  ),
                ],
                if (r == BeaconClosureReadiness.premature ||
                    r == BeaconClosureReadiness.notCloseable) ...[
                  FilledButton(
                    onPressed: onCloseBeacon,
                    child: Text(l10n.beaconCloseSheetActionCloseAnyway),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onPostUpdate();
                    },
                    child: Text(l10n.beaconCloseSheetActionPostUpdate),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.beaconCloseSheetActionKeepActive),
                  ),
                ],
                if (r == BeaconClosureReadiness.blocked) ...[
                  if (onResolveRoom != null)
                    FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onResolveRoom();
                      },
                      child: Text(l10n.beaconCloseSheetActionResolveRoom),
                    ),
                  if (kBeaconAllowForceCloseWhenBlocked)
                    TextButton(
                      onPressed: onCloseBeacon,
                      child: Text(l10n.beaconCloseSheetActionCloseAnyway),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.beaconCloseSheetActionNotNow),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}

Widget _evidenceRow(
  ColorScheme scheme,
  String text, {
  bool positive = true,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            positive ? Icons.check_circle_outline : Icons.info_outline,
            size: 18,
            color: positive ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TenturaText.body(scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
