import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

/// Detail payload for the NOW bottom sheet (beacon screen + room pin).
class BeaconNowDetailModel {
  const BeaconNowDetailModel({
    required this.whatsNextText,
    this.isPlaceholder = false,
    this.blockerTitle,
    this.blockerItem,
    this.publicStatus,
    this.coordinationStatus,
    this.lifecycle,
    this.lastChangeText,
    this.canEdit = false,
    this.onEdit,
  });

  final String whatsNextText;
  final bool isPlaceholder;
  final String? blockerTitle;
  final CoordinationItem? blockerItem;
  final int? publicStatus;
  final BeaconCoordinationStatus? coordinationStatus;
  final BeaconLifecycle? lifecycle;
  final String? lastChangeText;
  final bool canEdit;
  final VoidCallback? onEdit;
}

Future<void> showBeaconNowDetailSheet(
  BuildContext context, {
  required BeaconNowDetailModel model,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (ctx) => _BeaconNowDetailSheetBody(model: model),
  );
}

String beaconNowPublicStatusLine(L10n l10n, int publicStatus) =>
    switch (publicStatus) {
      0 => l10n.beaconPublicStatusOpen,
      1 => l10n.beaconPublicStatusCoordinating,
      2 => l10n.beaconPublicStatusMoreHelp,
      3 => l10n.beaconPublicStatusEnoughHelp,
      4 => l10n.beaconPublicStatusClosed,
      _ => l10n.beaconPublicStatusOpen,
    };

class _BeaconNowDetailSheetBody extends StatelessWidget {
  const _BeaconNowDetailSheetBody({required this.model});

  final BeaconNowDetailModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    final statusRows = <Widget>[];

    if (model.publicStatus != null) {
      statusRows.add(
        _situationLabeledRow(
          context,
          label: l10n.beaconSituationStateLabel,
          value: beaconNowPublicStatusLine(l10n, model.publicStatus!),
        ),
      );
    }

    if (model.lifecycle == BeaconLifecycle.reviewOpen ||
        model.lifecycle == BeaconLifecycle.closed) {
      if (model.coordinationStatus != null) {
        statusRows.add(
          _situationLabeledRow(
            context,
            label: l10n.beaconSituationStateLabel,
            value: coordinationStatusLabel(l10n, model.coordinationStatus!),
            valueColor: coordinationStatusOnSurfaceColor(
              scheme,
              model.coordinationStatus!,
            ),
          ),
        );
      }
    }

    final blockerTitle = model.blockerTitle?.trim();
    if (blockerTitle != null && blockerTitle.isNotEmpty) {
      final item = model.blockerItem;
      final kind = item?.kind ?? CoordinationItemKind.blocker;
      final status = item?.status ?? CoordinationItemStatus.open;
      statusRows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Text(
                  l10n.beaconSituationBlockerLabel,
                  style: TenturaText.typeLabel(scheme.onSurface),
                ),
              ),
              coordinationCompoundStatusIcon(
                kind: kind,
                status: status,
                tt: tt,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      blockerTitle,
                      style: TenturaText.body(scheme.onSurfaceVariant),
                    ),
                    if (item != null && item.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        item.body.trim(),
                        style: TenturaText.body(scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lastChange = model.lastChangeText?.trim();
    if (lastChange != null && lastChange.isNotEmpty) {
      statusRows.add(
        _situationLabeledRow(
          context,
          label: l10n.beaconSituationLastChangeLabel,
          value: lastChange,
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          kSpacingSmall,
          kSpacingMedium,
          kSpacingSmall,
          bottom + kSpacingMedium,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.beaconHudNowLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (statusRows.isNotEmpty) ...[
              const SizedBox(height: kSpacingMedium),
              ...statusRows,
            ],
            const SizedBox(height: kSpacingMedium),
            _situationLabeledRow(
              context,
              label: l10n.beaconSituationCurrentLineLabel,
              value: model.whatsNextText,
              valueColor: model.isPlaceholder
                  ? scheme.onSurfaceVariant
                  : scheme.onSurfaceVariant,
            ),
            if (model.canEdit && model.onEdit != null) ...[
              const SizedBox(height: kSpacingMedium),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    model.onEdit!();
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.beaconHudEditCurrentLineTitle),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _situationLabeledRow(
  BuildContext context, {
  required String label,
  required String value,
  Color? valueColor,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TenturaText.typeLabel(scheme.onSurface),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TenturaText.body(valueColor ?? scheme.onSurfaceVariant),
          ),
        ),
      ],
    ),
  );
}
