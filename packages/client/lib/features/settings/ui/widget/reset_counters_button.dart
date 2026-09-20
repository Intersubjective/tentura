import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/reset_counters_cubit.dart';

/// Settings **Reset counters** — D15.
///
/// The command is a *recheck*, so the copy says so and never suggests
/// erasure. A finished run says "Counters refreshed" and nothing more: the
/// account may still owe work, and the surfaces that show it are the ones
/// that say how much.
class ResetCountersButton extends StatefulWidget {
  const ResetCountersButton({super.key, this.cubit});

  /// U17d — the note about rows the repair could not fix.
  static const unrepairableKey = Key('attention-reset-counters-unrepairable');

  /// Injected by tests; production builds the cubit from the attention owner.
  final ResetCountersCubit? cubit;

  @override
  State<ResetCountersButton> createState() => _ResetCountersButtonState();
}

class _ResetCountersButtonState extends State<ResetCountersButton> {
  late final ResetCountersCubit _cubit = widget.cubit ?? ResetCountersCubit();

  @override
  void dispose() {
    if (widget.cubit == null) unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocConsumer<ResetCountersCubit, ResetCountersState>(
      bloc: _cubit,
      // One announcement per finished run: two identical outcomes in a row
      // are two events, so the serial is what distinguishes them.
      listenWhen: (previous, current) =>
          previous.outcomeSerial != current.outcomeSerial,
      listener: (context, state) {
        final failed = state.outcome == ResetCountersOutcome.failed;
        showSnackBar(
          context,
          text: failed
              ? l10n.attentionResetCountersFailed
              : l10n.attentionResetCountersDone,
          isError: failed,
        );
      },
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tt.rowGap,
        children: [
          TenturaCommandButton(
            key: const Key(TestIds.attentionResetCounters),
            label: l10n.attentionResetCounters,
            icon: const Icon(Icons.refresh_outlined),
            // The guard lives in the cubit too; disabling is what the user
            // sees of it.
            onPressed: state.isRunning ? null : _cubit.resetCounters,
          ),
          if (state.isRunning) ...[
            const LinearProgressIndicator(),
            TenturaMetaText(
              l10n.attentionResetCountersProgress,
              maxLines: 2,
            ),
          ],
          TenturaMetaText(
            l10n.attentionResetCountersExplanation,
            maxLines: 6,
            overflow: TextOverflow.visible,
          ),
          // U17d — `unrepairableObligationCount`. A correct run can still
          // come back with rows reconciliation cannot fix from their source,
          // and the person is owed that plainly: it is not a failure, it is
          // not work they owe, and there is no action here that would help.
          // Saying so beats inventing a button. It is shown only after a run
          // that answered — a failed run reports zero, so nothing lingers.
          if (state.unrepairableCount > 0)
            TenturaMetaText(
              key: ResetCountersButton.unrepairableKey,
              l10n.attentionResetCountersUnrepairable(state.unrepairableCount),
              maxLines: 6,
              overflow: TextOverflow.visible,
            ),
        ],
      ),
    );
  }
}
