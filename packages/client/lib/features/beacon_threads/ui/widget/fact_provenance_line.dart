import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// Who pinned a fact and who last edited it, e.g. `Anna · 3d ago` or
/// `Anna · edited by Boris +2 · 2h ago`.
///
/// [compact] drops the times for dense surfaces.
class FactProvenanceLine extends StatelessWidget {
  const FactProvenanceLine({
    required this.fact,
    this.compact = false,
    super.key,
  });

  final BeaconFactCard fact;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final edited =
        fact.revisionSeq > 1 ||
        fact.historyTruncated ||
        fact.status == BeaconFactCardStatusBits.corrected;

    final parts = <String>[
      if (fact.pinnedByTitle.isNotEmpty) fact.pinnedByTitle,
      if (!edited && !compact)
        compactRelativeTimeAgo(when: fact.createdAt, now: now, l10n: l10n),
      if (edited) _editedLabel(l10n),
      if (edited && !compact && fact.lastEditedAt != null)
        compactRelativeTimeAgo(when: fact.lastEditedAt!, now: now, l10n: l10n),
    ];

    return Text(
      parts.join(' · '),
      style: TenturaText.status(scheme.onSurfaceVariant),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _editedLabel(L10n l10n) {
    final editor = fact.lastEditedBy;
    final byOther = editor != null && editor != fact.pinnedBy;
    final extra = fact.otherEditorCount - (byOther ? 1 : 0);
    if (editor == null || fact.lastEditedByTitle.isEmpty) {
      return l10n.beaconRoomFactProvenanceEdited;
    }
    if (!byOther && extra <= 0) return l10n.beaconRoomFactProvenanceEdited;
    final name = extra > 0
        ? l10n.beaconRoomFactProvenanceEditorPlus(fact.lastEditedByTitle, extra)
        : fact.lastEditedByTitle;
    return l10n.beaconRoomFactProvenanceEditedBy(name);
  }
}
