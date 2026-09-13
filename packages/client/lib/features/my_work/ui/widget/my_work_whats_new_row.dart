import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

class MyWorkWhatsNewRow extends StatelessWidget {
  const MyWorkWhatsNewRow({
    required this.beacon,
    required this.viewModel,
    required this.currentUserId,
    required this.unseenCount,
    this.latestUnseen,
    super.key,
  });

  final Beacon beacon;
  final MyWorkCardViewModel viewModel;
  final String currentUserId;
  final int unseenCount;
  final AttentionReceipt? latestUnseen;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return Semantics(
      identifier: TestIds.myWorkWhatsNew(beacon.id),
      child: Padding(
        padding: EdgeInsets.only(top: tt.tightGap),
        child: unseenCount > 0 && latestUnseen != null
            ? _WhatsNewEmphasis(
                count: unseenCount,
                receipt: latestUnseen!,
                l10n: l10n,
              )
            : MyWorkLastEventBody(
                beacon: beacon,
                viewModel: viewModel,
                currentUserId: currentUserId,
                muted: true,
              ),
      ),
    );
  }
}

class _WhatsNewEmphasis extends StatelessWidget {
  const _WhatsNewEmphasis({
    required this.count,
    required this.receipt,
    required this.l10n,
  });

  final int count;
  final AttentionReceipt receipt;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final copy = resolveUpdatesFeedRowCopy(
      title: receipt.title,
      body: receipt.body,
      presentationKey: receipt.presentationKey,
      presentationPayloadJson: receipt.presentationPayloadJson,
      l10n: l10n,
    );
    final headline = copy.body.isNotEmpty ? copy.body : copy.headline;
    final label = l10n.myWorkWhatsNew(count, headline);
    return Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TenturaText.titleSmall(tt.text).copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
