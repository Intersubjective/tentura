import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/use_case/invite_accepted_setup_case.dart';
import '../bloc/updates_feed_cubit.dart';
import 'invite_accepted_receipt_card.dart';

/// Batch entry for three or more fresh pending invite prompts (architecture §5.5).
///
/// #259: «Skip all (N)» is the person's own confirmed decision for every
/// pending prompt in the sheet — never a timer (request-attention §4).
class PromptBatchSheet extends StatefulWidget {
  const PromptBatchSheet({required this.receipts, this.setup, super.key});

  final List<AttentionReceipt> receipts;

  /// Defaults to the registered [InviteAcceptedSetupPort].
  final InviteAcceptedSetupPort? setup;

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
  State<PromptBatchSheet> createState() => _PromptBatchSheetState();
}

/// What the last Skip all run achieved, shown in the sheet while it stays open.
sealed class _SkipAllOutcome {
  const _SkipAllOutcome();
}

final class _SkipAllPartial extends _SkipAllOutcome {
  const _SkipAllPartial(this.done, this.total);

  final int done;
  final int total;
}

final class _SkipAllFailed extends _SkipAllOutcome {
  const _SkipAllFailed();
}

class _PromptBatchSheetState extends State<PromptBatchSheet> {
  var _running = false;
  var _closed = false;
  _SkipAllOutcome? _outcome;

  InviteAcceptedSetupPort get _setup =>
      widget.setup ?? GetIt.I<InviteAcceptedSetupPort>();

  /// Receipts whose prompt is still known pending, in sheet order.
  List<AttentionReceipt> _pending(UpdatesFeedState state) => [
    for (final receipt in widget.receipts)
      if (inviteAcceptedPromptSubjectId(receipt) case final id?)
        if (state.promptProjectionFor(id).isKnownPending) receipt,
  ];

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _confirmSkipAll(int count) async {
    final l10n = L10n.of(context)!;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.promptBatchSkipAllConfirmTitle(count),
      content: l10n.promptBatchSkipAllConfirmBody,
      confirmLabel: l10n.promptBatchSkipAllConfirm,
      cancelLabel: l10n.buttonCancel,
    );
    if (confirmed != true || !mounted) return;
    await _skipAll();
  }

  /// Skips every still-pending prompt in order and reports only what it
  /// achieved. Retry runs this again: settled prompts are no longer pending,
  /// so only the rest are attempted.
  Future<void> _skipAll() async {
    if (_running) return;
    final l10n = L10n.of(context)!;
    final cubit = context.read<UpdatesFeedCubit>();
    final targets = _pending(cubit.state);
    if (targets.isEmpty) return;
    setState(() {
      _running = true;
      _outcome = null;
    });
    var done = 0;
    for (final receipt in targets) {
      final subjectId = inviteAcceptedPromptSubjectId(receipt)!;
      final projection = cubit.state.promptProjectionFor(subjectId);
      if (projection is! PromptProjectionKnown) continue;
      try {
        await _setup.skip(subjectId);
      } on Object {
        continue;
      }
      done++;
      if (cubit.isClosed) break;
      cubit.applyKnownPrompt(
        subjectId,
        projection.state.copyWith(state: PromptStateValue.skipped),
      );
    }
    if (!mounted) return;
    final total = targets.length;
    setState(() {
      _running = false;
      _outcome = done == total
          ? null
          : done == 0
          ? const _SkipAllFailed()
          : _SkipAllPartial(done, total);
    });
    if (done == total) {
      showSnackBar(context, text: l10n.promptBatchSkipAllDone(done));
    }
    if (_pending(cubit.state).isEmpty) _close();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final pendingCount = context.select<UpdatesFeedCubit, int>(
      (cubit) => _pending(cubit.state).length,
    );
    final outcome = _outcome;
    return BlocListener<UpdatesFeedCubit, UpdatesFeedState>(
      // Settled one by one from the rows: close once nothing is pending.
      listenWhen: (prev, curr) =>
          !_running && _pending(prev).isNotEmpty && _pending(curr).isEmpty,
      listener: (_, _) => _close(),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  tt.screenHPadding,
                  tt.rowGap,
                  tt.screenHPadding - 12,
                  tt.rowGap,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.inviteAcceptedSetupTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (pendingCount > 0)
                      TenturaTextAction(
                        label: l10n.promptBatchSkipAll(pendingCount),
                        onPressed: _running
                            ? null
                            : () => unawaited(_confirmSkipAll(pendingCount)),
                      ),
                  ],
                ),
              ),
              if (outcome != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          switch (outcome) {
                            _SkipAllPartial(:final done, :final total) =>
                              l10n.promptBatchSkipAllPartial(done, total),
                            _SkipAllFailed() =>
                              l10n.inviteAcceptedSetupSkipError,
                          },
                          style: TenturaText.body(
                            outcome is _SkipAllFailed ? tt.danger : tt.warn,
                          ),
                        ),
                      ),
                      if (outcome is _SkipAllPartial)
                        TenturaTextAction(
                          label: l10n.promptBatchSkipAllRetry,
                          onPressed: _running
                              ? null
                              : () => unawaited(_skipAll()),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.only(bottom: tt.sectionGap),
                  itemCount: widget.receipts.length,
                  separatorBuilder: (_, _) => const TenturaHairlineDivider(),
                  itemBuilder: (context, index) {
                    final receipt = widget.receipts[index];
                    return _BatchReceiptRow(receipt: receipt);
                  },
                ),
              ),
            ],
          );
        },
      ),
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
