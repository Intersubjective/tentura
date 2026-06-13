import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/forward_candidate.dart';
import '../bloc/lineage_suggestions_preview_cubit.dart';
import '../bloc/lineage_suggestions_preview_state.dart';
import 'forward_recipient_row.dart';

Future<void> showLineageSuggestionsPreviewSheet(
  BuildContext context, {
  required String beaconId,
}) async {
  final cubit = GetIt.I<LineageSuggestionsPreviewCubit>();
  await cubit.load(beaconId);
  if (!context.mounted) return;
  final l10n = L10n.of(context)!;
  final tt = context.tt;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return BlocProvider.value(
        value: cubit,
        child: BlocBuilder<LineageSuggestionsPreviewCubit,
            LineageSuggestionsPreviewState>(
          builder: (context, state) {
            final maxH = MediaQuery.sizeOf(context).height * 0.85;
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    tt.screenHPadding,
                    tt.rowGap,
                    tt.screenHPadding,
                    tt.screenHPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history, size: tt.iconSize, color: tt.textMuted),
                          SizedBox(width: tt.rowGap * 0.5),
                          Expanded(
                            child: Text(
                              l10n.beaconLineagePreviewTitle,
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: tt.rowGap * 0.5),
                      Text(
                        l10n.beaconLineagePreviewSubjectivity,
                        style: TenturaText.bodySmall(tt.textMuted),
                      ),
                      SizedBox(height: tt.rowGap),
                      Expanded(
                        child: _PreviewBody(state: state, l10n: l10n),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.state, required this.l10n});

  final LineageSuggestionsPreviewState state;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (state.hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.beaconLineagePreviewError),
            TextButton(
              onPressed: () => context
                  .read<LineageSuggestionsPreviewCubit>()
                  .load(state.beaconId),
              child: Text(l10n.beaconLineagePreviewRetry),
            ),
          ],
        ),
      );
    }
    if (state.rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: context.tt.textMuted),
            const SizedBox(height: 8),
            Text(
              l10n.beaconLineagePreviewEmpty,
              textAlign: TextAlign.center,
              style: TenturaText.bodySmall(context.tt.textMuted),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: state.rows.length,
      separatorBuilder: (_, __) => const TenturaHairlineDivider(),
      itemBuilder: (context, i) {
        final row = state.rows[i];
        return ForwardRecipientRow(
          candidate: ForwardCandidate(
            profile: row.profile,
            lineageGroup: row.group,
            lineageReasonCode: row.reasonCode,
            lineageReasonArg: row.reasonArg,
          ),
          isSelected: false,
          onToggle: null,
        );
      },
    );
  }
}
