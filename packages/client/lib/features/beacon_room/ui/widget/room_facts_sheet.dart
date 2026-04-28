import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Lists pinned facts for the current beacon (server-filtered visibility).
Future<void> showRoomFactsSheet(
  BuildContext context, {
  required List<BeaconFactCard> facts,
}) {
  final l10n = L10n.of(context)!;
  final tt = context.tt;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: kPaddingH.add(kPaddingSmallT),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.beaconFactsSheetTitle, style: Theme.of(ctx).textTheme.titleMedium),
            SizedBox(height: tt.rowGap),
            if (facts.isEmpty)
              Text(
                l10n.beaconFactsSheetEmpty,
                style: TenturaText.body(tt.textMuted),
              )
            else
              ListView(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: [
                  for (final f in facts)
                    Padding(
                      padding: EdgeInsets.only(bottom: tt.rowGap),
                      child: SelectableText(
                        f.factText,
                        style: TenturaText.body(tt.text),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
