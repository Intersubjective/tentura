import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluations_written_about_viewer.dart';
import 'package:tentura/features/evaluation/ui/widget/received_review_body.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import '../bloc/profile_reviews_about_me_cubit.dart';
import '../bloc/profile_view_cubit.dart';

class ReviewsAboutMeFromProfileSliver extends StatelessWidget {
  const ReviewsAboutMeFromProfileSliver({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ProfileReviewsAboutMeCubit, ProfileReviewsAboutMeState>(
        builder: (context, state) {
          if (state.isLoading && state.rows.isEmpty) {
            return const SliverToBoxAdapter(
              child: Padding(padding: kPaddingSmallT, child: LinearPiActive()),
            );
          }
          if ((state.hasError && state.rows.isEmpty) || state.rows.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          final l10n = L10n.of(context)!;
          final owner = context
              .read<ProfileViewCubit>()
              .state
              .profile
              .displayName;
          return SliverToBoxAdapter(
            child: Padding(
              padding: kPaddingAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionHeader(
                    label: l10n.profileReviewsFromPersonSectionTitle(owner),
                  ),
                  for (var i = 0; i < state.rows.length; i++)
                    _ProfileReviewRow(
                      row: state.rows[i],
                      showDivider: i < state.rows.length - 1,
                    ),
                ],
              ),
            ),
          );
        },
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      top: context.tt.sectionGap,
      bottom: context.tt.rowGap,
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ProfileReviewRow extends StatelessWidget {
  const _ProfileReviewRow({required this.row, required this.showDivider});
  final EvaluationsWrittenAboutViewerRow row;
  final bool showDivider;
  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: tt.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.beaconId.isEmpty)
                Text(
                  row.beaconTitle,
                  style: TenturaText.title(
                    Theme.of(context).colorScheme.onSurface,
                  ),
                )
              else
                TenturaTextAction(
                  label: row.beaconTitle,
                  onPressed: () =>
                      context.read<ScreenCubit>().showBeacon(row.beaconId),
                ),
              SizedBox(height: tt.tightGap),
              ReceivedReviewBody(
                wireValue: row.value,
                acknowledgedHelpTags: row.acknowledgedHelpTags,
                note: row.note,
                reasonTags: row.reasonTags,
                occurredAt: row.occurredAt,
              ),
            ],
          ),
        ),
        if (showDivider) const TenturaHairlineDivider(),
      ],
    );
  }
}
