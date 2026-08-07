import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluations_written_about_viewer.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/evaluation_received_trust_tone_line.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/profile_reviews_about_me_cubit.dart';
import '../bloc/profile_view_cubit.dart';

class ReviewsAboutMeFromProfileSliver extends StatelessWidget {
  const ReviewsAboutMeFromProfileSliver({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileReviewsAboutMeCubit, ProfileReviewsAboutMeState>(
      builder: (context, state) {
        if (state.isLoading && state.rows.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: kPaddingSmallT,
              child: LinearPiActive(),
            ),
          );
        }

        if (state.hasError && state.rows.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        if (state.rows.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final profileOwnerName = context
            .read<ProfileViewCubit>()
            .state
            .profile
            .displayName;
        final l10n = L10n.of(context)!;

        return SliverToBoxAdapter(
          child: Padding(
            padding: kPaddingAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  label: l10n.profileReviewsFromPersonSectionTitle(
                    profileOwnerName,
                  ),
                ),
                for (var i = 0; i < state.rows.length; i++)
                  _ReviewsAboutMeFromProfileRow(
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: kSpacingMedium, bottom: kSpacingSmall),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ReviewsAboutMeFromProfileRow extends StatelessWidget {
  const _ReviewsAboutMeFromProfileRow({
    required this.row,
    required this.showDivider,
  });

  final EvaluationsWrittenAboutViewerRow row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final ageLabel = compactRelativeTimeAgo(
      when: row.occurredAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final tone = _toneFor(row.trustTone);
    final icon = _iconFor(row.trustTone);
    final iconColor = row.trustTone == EvaluationReceivedTrustTone.noBasis
        ? tt.textFaint
        : tenturaToneColor(tt, tone);
    final iconBackground = row.trustTone == EvaluationReceivedTrustTone.noBasis
        ? tt.surface
        : iconColor.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: tt.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EvaluationTrustToneGlyph(
                icon: icon,
                backgroundColor: iconBackground,
                iconColor: iconColor,
              ),
              SizedBox(width: tt.iconTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BeaconTitle(
                      beaconId: row.beaconId,
                      title: row.beaconTitle,
                    ),
                    SizedBox(height: tt.tightGap),
                    _TrustLabelAndNote(
                      trustTone: row.trustTone,
                      note: row.note,
                      l10n: l10n,
                    ),
                    SizedBox(height: tt.rowGap),
                    TenturaMetaText(ageLabel),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const TenturaHairlineDivider(),
      ],
    );
  }

  TenturaTone _toneFor(EvaluationReceivedTrustTone trustTone) =>
      switch (trustTone) {
        EvaluationReceivedTrustTone.up => TenturaTone.good,
        EvaluationReceivedTrustTone.down => TenturaTone.danger,
        EvaluationReceivedTrustTone.noChange => TenturaTone.neutral,
        EvaluationReceivedTrustTone.noBasis => TenturaTone.neutral,
      };

  IconData _iconFor(EvaluationReceivedTrustTone trustTone) =>
      switch (trustTone) {
        EvaluationReceivedTrustTone.up => Icons.arrow_upward,
        EvaluationReceivedTrustTone.down => Icons.arrow_downward,
        EvaluationReceivedTrustTone.noChange => Icons.remove,
        EvaluationReceivedTrustTone.noBasis => Icons.help_outline,
      };
}

String _trustLabel(L10n l10n, EvaluationReceivedTrustTone trustTone) =>
    switch (trustTone) {
      EvaluationReceivedTrustTone.up => l10n.evaluationReceivedTrustUpLabel,
      EvaluationReceivedTrustTone.down => l10n.evaluationReceivedTrustDownLabel,
      EvaluationReceivedTrustTone.noChange => l10n.evaluationReceivedNeutralLabel,
      EvaluationReceivedTrustTone.noBasis => l10n.evaluationReceivedNoBasisLabel,
    };

class _TrustLabelAndNote extends StatelessWidget {
  const _TrustLabelAndNote({
    required this.trustTone,
    required this.note,
    required this.l10n,
  });

  final EvaluationReceivedTrustTone trustTone;
  final String note;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final colors = Theme.of(context).colorScheme;
    final label = _trustLabel(l10n, trustTone);
    final trimmedNote = note.trim();

    if (trustTone == EvaluationReceivedTrustTone.noBasis) {
      return Text(
        trimmedNote.isEmpty ? label : '$label · $trimmedNote',
        style: TenturaText.status(tt.textFaint),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      );
    }

    final tone = switch (trustTone) {
      EvaluationReceivedTrustTone.up => TenturaTone.good,
      EvaluationReceivedTrustTone.down => TenturaTone.danger,
      EvaluationReceivedTrustTone.noChange => TenturaTone.neutral,
      EvaluationReceivedTrustTone.noBasis => TenturaTone.neutral,
    };

    if (trimmedNote.isEmpty) {
      return TenturaStatusText(label, tone: tone, maxLines: null);
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: label,
            style: TenturaText.status(tenturaToneColor(tt, tone)),
          ),
          TextSpan(
            text: ' · $trimmedNote',
            style: TenturaText.body(colors.onSurface),
          ),
        ],
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _BeaconTitle extends StatelessWidget {
  const _BeaconTitle({
    required this.beaconId,
    required this.title,
  });

  final String beaconId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (beaconId.isEmpty) {
      return Text(
        title,
        style: TenturaText.title(colors.onSurface),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    return TenturaTextAction(
      label: title,
      onPressed: () => context.read<ScreenCubit>().showBeacon(beaconId),
    );
  }
}
