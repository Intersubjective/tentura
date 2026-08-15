import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_definition_body.dart';
import 'package:tentura/features/capability/ui/widget/capability_requirement_tags.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_location_actions.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

/// Whether the request HUD should show the Details affordance.
bool beaconViewHasDetailsContent(Beacon beacon) {
  if (beacon.hasScheduleDates) return true;
  if (beacon.coordinates?.isNotEmpty ?? false) return true;
  if (beacon.description.trim().isNotEmpty) return true;
  if (resolveCapabilityRequirementTags(beacon.needs).isNotEmpty) return true;
  if (beacon.hasPicture) return true;
  return false;
}

Future<void> showBeaconViewDetailsSheet(
  BuildContext context, {
  required Beacon beacon,
}) {
  final l10n = L10n.of(context)!;

  return showTenturaAdaptiveSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final sheetTt = ctx.tt;
      final muted = sheetTt.textMuted;
      final children = <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            sheetTt.screenHPadding,
            sheetTt.tightGap * 2,
            sheetTt.screenHPadding,
            sheetTt.rowGap,
          ),
          child: Text(
            l10n.beaconDetailsSection,
            style: Theme.of(ctx).textTheme.titleSmall,
          ),
        ),
      ];

      if (beacon.hasScheduleDates) {
        final scheduleText =
            '${dateFormatYMD(beacon.startAt)} - ${dateFormatYMD(beacon.endAt)}';
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sheetTt.screenHPadding),
            child: BeaconHudIconRow(
              leadIcon: BeaconHudRowIcons.schedule,
              semanticsLabel: scheduleText,
              body: HudLabeledMultiline(
                leadingIcon: BeaconHudRowIcons.schedule,
                semanticsLabel: scheduleText,
                text: scheduleText,
                mutedColor: muted,
                includeLead: false,
                primaryMaxLines: 10,
                showTruncationHint: false,
              ),
            ),
          ),
        );
        children.add(SizedBox(height: sheetTt.rowGap));
      }

      if (beacon.coordinates?.isNotEmpty ?? false) {
        final locationText = beaconHudLocationDisplayLabel(beacon, l10n);
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sheetTt.screenHPadding),
            child: Material(
              color: Colors.transparent,
              child: Semantics(
                button: true,
                label: l10n.beaconCardLocationSemantics(locationText),
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => showBeaconLocationActions(ctx, beacon),
                    borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
                    child: BeaconHudIconRow(
                      leadIcon: BeaconHudRowIcons.location,
                      semanticsLabel:
                          l10n.beaconCardLocationSemantics(locationText),
                      body: HudLabeledMultiline(
                        leadingIcon: BeaconHudRowIcons.location,
                        semanticsLabel:
                            l10n.beaconCardLocationSemantics(locationText),
                        text: locationText,
                        mutedColor: muted,
                        includeLead: false,
                        primaryMaxLines: 10,
                        showTruncationHint: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        children.add(SizedBox(height: sheetTt.rowGap));
      }

      children.add(
        Padding(
          padding: EdgeInsets.only(
            left: sheetTt.screenHPadding,
            right: sheetTt.screenHPadding,
            bottom: sheetTt.cardPadding.bottom,
          ),
          child: BeaconDefinitionBody(beacon: beacon),
        ),
      );

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      );
    },
  );
}

/// HUD metadata row trailing chevron for the Details affordance.
Widget beaconViewDetailsHudTrailing(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Icon(
    Icons.chevron_right,
    size: context.tt.iconSize,
    color: scheme.onSurfaceVariant,
  );
}
