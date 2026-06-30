import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/hud_multiline_body.dart';

import 'beacon_definition_body.dart';

/// Collapsible definition row in the beacon HUD (below NOW/YOU, above CTA rail).
class BeaconDefinitionHudRow extends StatefulWidget {
  const BeaconDefinitionHudRow({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  @override
  State<BeaconDefinitionHudRow> createState() => _BeaconDefinitionHudRowState();
}

class _BeaconDefinitionHudRowState extends State<BeaconDefinitionHudRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final beacon = widget.beacon;
    final needText = beacon.needSummary?.trim() ?? '';
    final hasNeed = needText.isNotEmpty;
    final primaryText =
        hasNeed ? needText : l10n.beaconDefinitionSectionTitle;
    final primaryStyle = TenturaText.hudBodySmall(
      hasNeed ? scheme.onSurface : tt.textMuted,
    );
    final showMoreStyle = TenturaText.hudBodySmall(scheme.primary);

    if (_expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BeaconHudIconRow(
            leadIcon: Icons.info_outline,
            semanticsLabel: l10n.beaconDefinitionSectionTitle,
            leadAlign: BeaconHudRowLeadAlign.start,
            body: Text(
              primaryText,
              style: primaryStyle,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: kBeaconHudRowLeadWidth,
              top: tt.tightGap,
            ),
            child: BeaconDefinitionBody(
              key: ValueKey('hud-def-${beacon.id}'),
              beacon: beacon,
              includeNeedSummary: false,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(
                left: kBeaconHudRowLeadWidth,
                top: tt.rowGap / 2,
              ),
              child: Semantics(
                button: true,
                label: l10n.itemShowLess,
                child: InkWell(
                  onTap: () => setState(() => _expanded = false),
                  borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: tt.rowGap / 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.itemShowLess, style: showMoreStyle),
                        Icon(
                          Icons.expand_less,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyMaxWidth = constraints.maxWidth - kBeaconHudRowLeadWidth;
        final exceeds = HudMultilineLayout.textExceedsMaxLines(
          text: primaryText,
          style: primaryStyle,
          maxWidth: bodyMaxWidth,
          maxLines: HudMultilineBody.defaultPrimaryMaxLines,
        );
        final showMoreAffordance =
            exceeds || _hasExpandableDefinitionContent(beacon);

        return BeaconHudIconRow(
          leadIcon: Icons.info_outline,
          semanticsLabel: l10n.beaconDefinitionSectionTitle,
          leadAlign: BeaconHudRowLeadAlign.start,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                primaryText,
                maxLines: HudMultilineBody.defaultPrimaryMaxLines,
                overflow: TextOverflow.ellipsis,
                style: primaryStyle,
              ),
              if (showMoreAffordance) ...[
                const SizedBox(height: 2),
                Semantics(
                  button: true,
                  label: l10n.itemShowMore,
                  child: InkWell(
                    onTap: () => setState(() => _expanded = true),
                    borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: tt.rowGap / 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.itemShowMore, style: showMoreStyle),
                          if (beacon.hasPicture) ...[
                            Text(
                              '+${beacon.images.length}',
                              style: showMoreStyle,
                            ),
                            Icon(
                              Icons.image_outlined,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  bool _hasExpandableDefinitionContent(Beacon beacon) {
    final doneWhen = beacon.successCriteria?.trim();
    return beacon.startAt != null ||
        beacon.endAt != null ||
        (beacon.coordinates?.isNotEmpty ?? false) ||
        (doneWhen != null && doneWhen.isNotEmpty) ||
        beacon.needs.isNotEmpty ||
        beacon.hasPicture ||
        beacon.description.trim().isNotEmpty;
  }
}
