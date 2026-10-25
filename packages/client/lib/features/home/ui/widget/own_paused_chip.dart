import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

/// Your own pause, shown beside your avatar outside the profile (#267):
/// "Paused until `<date>`" while you are not taking new requests; tapping it
/// offers to resume. Nothing at all while you are open or only limited.
class OwnPausedChip extends StatelessWidget {
  const OwnPausedChip({
    this.profileCubit,
    this.clock,
    this.iconOnly = false,
    super.key,
  });

  static const chipKey = Key('own-paused-chip');

  /// Defaults to the global [ProfileCubit] when registered.
  final ProfileCubit? profileCubit;

  /// Test-only clock for "today".
  final DateTime Function()? clock;

  /// A pause glyph with the label as its tooltip, for a collapsed rail.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final cubit =
        profileCubit ??
        (GetIt.I.isRegistered<ProfileCubit>() ? GetIt.I<ProfileCubit>() : null);
    if (cubit == null) return const SizedBox.shrink();
    return BlocBuilder<ProfileCubit, ProfileState>(
      bloc: cubit,
      buildWhen: (p, c) => p.profile.availability != c.profile.availability,
      builder: (context, state) {
        final availability = state.profile.availability;
        final todayUtc = availabilityTodayUtc(clock);
        final resumeOn = availability.resumeOn;
        if (resumeOn == null ||
            availability.effectiveOn(todayUtc) != AvailabilityView.paused) {
          return const SizedBox.shrink();
        }
        final l10n = L10n.of(context)!;
        final label = l10n.availabilityPausedChip(
          availabilityWhenLabel(l10n, resumeOn, todayUtc),
        );
        void onPressed() => unawaited(_confirmResume(context, cubit));
        if (iconOnly) {
          return IconButton(
            key: chipKey,
            tooltip: label,
            onPressed: onPressed,
            icon: const Icon(Icons.pause_circle_outline),
          );
        }
        return ActionChip(
          key: chipKey,
          avatar: const Icon(Icons.pause_circle_outline),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        );
      },
    );
  }

  static Future<void> _confirmResume(
    BuildContext context,
    ProfileCubit cubit,
  ) async {
    if (cubit.isAvailabilityResumeInFlight) return;
    final l10n = L10n.of(context)!;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.availabilityResumeConfirmTitle,
      content: l10n.availabilityResumeConfirmBody,
      confirmLabel: l10n.availabilityResumeNow,
      cancelLabel: l10n.buttonCancel,
    );
    if (confirmed ?? false) await cubit.resumeAvailability();
  }
}
