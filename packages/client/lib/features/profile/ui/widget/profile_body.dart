import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/tentura_fullscreen_image_viewer.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura_root/domain/enums.dart';

import '../bloc/profile_cubit.dart';
import '../sheet/availability_sheet.dart';

TenturaTone _ownAvailabilityPrimaryTone(
  Availability availability,
  DateTime todayUtc,
) =>
    switch (availability.effectiveOn(todayUtc)) {
      AvailabilityView.open => TenturaTone.neutral,
      AvailabilityView.limited => TenturaTone.info,
      AvailabilityView.paused => TenturaTone.warn,
    };

/// Own-profile availability status and Change action (architecture §9.2).
class OwnProfileAvailabilityControl extends StatelessWidget {
  const OwnProfileAvailabilityControl({
    required this.profile,
    required this.todayUtc,
    this.onChange,
    super.key,
  });

  final Profile profile;
  final DateTime todayUtc;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final availability = profile.availability;
    final primaryLine = ownAvailabilityPrimaryLine(l10n, availability, todayUtc);
    final secondaryLine =
        ownAvailabilitySecondaryLine(l10n, availability, todayUtc);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TenturaStatusText(
                primaryLine,
                tone: _ownAvailabilityPrimaryTone(availability, todayUtc),
                maxLines: null,
                softWrap: true,
              ),
              if (secondaryLine != null) ...[
                SizedBox(height: tt.rowGap),
                TenturaStatusText(
                  secondaryLine,
                  tone: TenturaTone.info,
                  maxLines: null,
                  softWrap: true,
                ),
              ],
            ],
          ),
        ),
        TenturaTextAction(
          key: const Key('availability_change_action'),
          label: l10n.availabilityChangeAction,
          onPressed: onChange,
        ),
      ],
    );
  }
}

class ProfileBody extends StatelessWidget {
  const ProfileBody({
    required this.profile,
    this.profileCubit,
    this.clock,
    super.key,
  });

  final Profile profile;
  final ProfileCubit? profileCubit;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tt = context.tt;
    final screenCubit = context.read<ScreenCubit>();
    final sectionTop = EdgeInsets.only(top: tt.sectionGap);
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Avatar
          Center(
            child: profile.hasAvatar
                ? GestureDetector(
                    onTap: () =>
                        openProfileAvatarFullscreen(context, profile),
                    child: SelfAwareAvatar.big(
                      profile: profile,
                    ),
                  )
                : SelfAwareAvatar.big(
                    profile: profile,
                  ),
          ),

          // Description
          Padding(
            padding: sectionTop,
            child: ShowMoreText(
              profile.description,
              style: textTheme.bodyMedium,
              colorClickableText: theme.colorScheme.primary,
            ),
          ),

          Padding(
            padding: sectionTop,
            child: BlocBuilder<ProfileCubit, ProfileState>(
              bloc: profileCubit ?? GetIt.I<ProfileCubit>(),
              builder: (context, state) {
                final todayUtc = availabilityTodayUtc(clock);
                return OwnProfileAvailabilityControl(
                  profile: state.profile,
                  todayUtc: todayUtc,
                  onChange: () => showAvailabilitySheet(
                    context,
                    profileCubit: profileCubit ?? GetIt.I<ProfileCubit>(),
                    clock: clock,
                  ),
                );
              },
            ),
          ),

          // Show Connections
          Padding(
            padding: sectionTop,
            child: OutlinedButton.icon(
              onPressed: () => screenCubit.showGraphFor(profile.id),
              icon: const Icon(TenturaIcons.graph),
              label: Text(l10n.showConnections),
            ),
          ),

          Padding(
            padding: sectionTop,
            child: OutlinedButton.icon(
              onPressed: screenCubit.showInviteGenealogy,
              icon: const Icon(Icons.device_hub_outlined),
              label: Text(l10n.showInviteGenealogy),
            ),
          ),

          // Show Beacons
          Padding(
            padding: sectionTop,
            child: OutlinedButton.icon(
              onPressed: () => screenCubit.showBeaconsOf(profile.id),
              icon: const Icon(Icons.open_in_full),
              label: Text(l10n.showBeacons),
            ),
          ),

          Padding(
            padding: sectionTop,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.settings),
              label: Text(l10n.labelSettings),
              onPressed: screenCubit.showSettings,
            ),
          ),
        ],
      ),
    );
  }
}
