import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/polling_cubit.dart';

class PollDialog extends StatefulWidget {
  static Future<void> show(
    BuildContext context, {
    required Polling polling,
  }) => showAdaptiveDialog<void>(
    context: context,
    builder: (_) => PollDialog(
      polling: polling,
    ),
  );

  const PollDialog({required this.polling, super.key});

  final Polling polling;

  @override
  State<PollDialog> createState() => PollDialogState();
}

class PollDialogState extends State<PollDialog> {
  late final _l10n = L10n.of(context)!;

  late final _theme = Theme.of(context);

  late final _pollingCubit = PollingCubit(polling: widget.polling);

  @override
  void initState() {
    super.initState();
    unawaited(_pollingCubit.fetch());
  }

  @override
  void dispose() {
    unawaited(_pollingCubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    contentPadding: kPaddingAll,
    insetPadding: kPaddingAll,
    scrollable: true,

    // Title
    title: Text(
      _l10n.pollDialogTitle,
      style: _theme.textTheme.bodyMedium,
      textAlign: TextAlign.center,
    ),

    // Body
    content: BlocConsumer<PollingCubit, PollingState>(
      key: ObjectKey(_pollingCubit),
      bloc: _pollingCubit,
      listenWhen: (p, c) => p.status != c.status,
      listener: commonScreenBlocListener,
      buildWhen: (p, c) => c.isSuccess,
      builder: (context, state) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Loader
            LinearPiActive.builder(context, state.isLoading),

            // Polling Question
            Padding(
              padding: const EdgeInsets.only(bottom: kSpacingMedium),
              child: Text(state.polling.question),
            ),
            const Divider(),

            // Variants
            ...state.polling.variants.entries.map(
              (variant) {
                final isSelected = variant.key == state.chosenVariant;
                late final result = state.results.firstWhere(
                  (e) => e.pollingVariantId == variant.key,
                  orElse: () => (
                    pollingVariantId: variant.key,
                    immediateResult: 0,
                    finalResult: 0,
                    percentageVoted: 0,
                    votesCount: 0,
                  ),
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  selected: isSelected,

                  // Radion Icon
                  leading: Icon(
                    isSelected ? Icons.radio_button_on : Icons.radio_button_off,
                  ),

                  // Question
                  title: Text(
                    variant.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _theme.textTheme.bodyMedium,
                  ),

                  // Results
                  subtitle: state.hasResults
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // immediate result
                            Text(
                              '${_l10n.immediateLabel} '
                              '${(100 * (result.immediateResult)).round()} %',
                              style: _theme.textTheme.bodySmall,
                            ),
                            // final result
                            Text(
                              '${_l10n.finalLabel} '
                              '${(100 * (result.finalResult)).round()} %',
                              style: _theme.textTheme.bodySmall,
                            ),
                          ],
                        )
                      : null,

                  // Count
                  trailing: state.hasResults
                      ? Text(
                          result.votesCount.toString(),
                          style: _theme.textTheme.bodyMedium,
                        )
                      : null,
                  onTap: state.hasResults
                      ? null
                      : () => _pollingCubit.chooseVariant(variant.key),
                );
              },
            ),
            const Divider(),

            // Total votes
            Padding(
              padding: kPaddingV,
              child: Text(
                _l10n.votedCountText(
                  state.results.firstOrNull?.percentageVoted ?? 0,
                  state.results.isEmpty
                      ? 0
                      : state.results
                            .map((e) => e.votesCount)
                            .reduce((v, e) => v + e),
                ),
                style: _theme.textTheme.bodySmall!.copyWith(
                  color: _theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    ),

    // Buttons
    actions: [
      // Send choice
      BlocSelector<PollingCubit, PollingState, bool>(
        bloc: _pollingCubit,
        selector: (state) => state.canVote,
        builder: (_, canVote) => FilledButton(
          onPressed: canVote ? _pollingCubit.vote : null,
          child: Text(_l10n.voteButton),
        ),
      ),

      // Close
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: Text(_l10n.closeButton),
      ),
    ],
  );
}
