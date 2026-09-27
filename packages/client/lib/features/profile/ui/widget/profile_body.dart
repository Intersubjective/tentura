import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/sheet/how_tentura_works_sheet.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/tentura_fullscreen_image_viewer.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura_root/domain/enums.dart';

import '../bloc/profile_cubit.dart';
import '../sheet/availability_sheet.dart';

TenturaTone _ownAvailabilityPrimaryTone(
  Availability availability,
  DateTime todayUtc,
) => switch (availability.effectiveOn(todayUtc)) {
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
    final primaryLine = ownAvailabilityPrimaryLine(
      l10n,
      availability,
      todayUtc,
    );
    final secondaryLine = ownAvailabilitySecondaryLine(
      l10n,
      availability,
      todayUtc,
    );

    // Centred: the Change action's 44 dp target sat on another baseline
    // than the one-line status it changes.
    return Row(
      crossAxisAlignment: secondaryLine == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
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
                    onTap: () => openProfileAvatarFullscreen(context, profile),
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
            child: TenturaSelectionArea(
              child: ShowMoreText(
                profile.description,
                style: textTheme.bodyMedium,
                colorClickableText: theme.colorScheme.primary,
                annotations: buildUrlAnnotations(linkColor: tt.info),
              ),
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

          Padding(
            padding: sectionTop,
            child: TenturaMenuGroup(
              title: l10n.profileSectionNetwork,
              children: [
                TenturaMenuTile(
                  icon: TenturaIcons.graph,
                  title: l10n.showConnections,
                  onTap: () => screenCubit.showGraphFor(profile.id),
                ),
                TenturaMenuTile(
                  icon: Icons.device_hub_outlined,
                  title: l10n.showInviteGenealogy,
                  onTap: screenCubit.showInviteGenealogy,
                ),
                TenturaMenuTile(
                  icon: Icons.campaign_outlined,
                  title: l10n.showBeacons,
                  onTap: () => screenCubit.showBeaconsOf(profile.id),
                ),
              ],
            ),
          ),
          Padding(
            padding: sectionTop,
            child: TenturaMenuGroup(
              title: l10n.settingsSectionApp,
              children: [
                TenturaMenuTile(
                  icon: Icons.help_outline,
                  title: l10n.orientationReopen,
                  onTap: () => showHowTenturaWorksSheet(
                    context,
                    onOpenTab: (tab) =>
                        AutoTabsRouter.of(context).setActiveIndex(
                          HomeTabSpec.forTab(tab).index,
                        ),
                  ),
                ),
                TenturaMenuTile(
                  icon: Icons.settings_outlined,
                  title: l10n.labelSettings,
                  onTap: screenCubit.showSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
