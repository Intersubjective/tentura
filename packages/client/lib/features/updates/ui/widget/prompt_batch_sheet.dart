import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/updates_feed_cubit.dart';
import 'invite_accepted_receipt_card.dart';

/// Batch entry for three or more fresh pending invite prompts (architecture §5.5).
class PromptBatchSheet extends StatelessWidget {
  const PromptBatchSheet({required this.receipts, super.key});

  final List<AttentionReceipt> receipts;

  static Future<void> show({
    required BuildContext context,
    required UpdatesFeedCubit cubit,
    required List<AttentionReceipt> receipts,
  }) => showTenturaAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => BlocProvider.value(
      value: cubit,
      child: PromptBatchSheet(receipts: receipts),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                tt.screenHPadding,
                tt.rowGap,
                tt.screenHPadding,
                tt.rowGap,
              ),
              child: Text(
                l10n.inviteAcceptedSetupTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: EdgeInsets.only(bottom: tt.sectionGap),
                itemCount: receipts.length,
                separatorBuilder: (_, _) => const TenturaHairlineDivider(),
                itemBuilder: (context, index) {
                  final receipt = receipts[index];
                  return _BatchReceiptRow(receipt: receipt);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BatchReceiptRow extends StatelessWidget {
  const _BatchReceiptRow({required this.receipt});

  final AttentionReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final subjectId = receipt.actorUserId ?? receipt.targetEntityId;
    final cubit = context.read<UpdatesFeedCubit>();
    return BlocSelector<UpdatesFeedCubit, UpdatesFeedState, PromptProjection>(
      selector: (state) => subjectId == null
          ? const PromptProjection.unknown()
          : state.promptProjectionFor(subjectId),
      builder: (context, projection) {
        return InviteAcceptedReceiptCard(
          key: ValueKey(receipt.id),
          receipt: receipt,
          promptProjection: projection,
          onRetryPromptFetch: cubit.retryPromptFetch,
          onPromptSettled: cubit.applyKnownPrompt,
          onTap: () {},
          onMarkSeen: () => cubit.markSeen(receipt.id),
          onMarkUnseen: () => unawaited(cubit.markUnseen(receipt.id)),
        );
      },
    );
  }
}
