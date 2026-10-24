import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/sheet/how_tentura_works_sheet.dart';
import 'package:tentura/features/profile/ui/dialog/my_profile_delete.dart';

import '../bloc/settings_cubit.dart';
import '../widget/language_switch_button.dart';
import '../widget/noisy_wall_tile.dart';
import '../widget/reset_counters_button.dart';
import '../widget/theme_switch_button.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/consts.dart';

@RoutePage()
class SettingsScreen extends StatefulWidget implements AutoRouteWrapper {
  const SettingsScreen({
    super.key,
    this.peopleTagsEnabled,
  });

  /// Defaults to [kPeopleTagsEnabled]; null because the generated route
  /// cannot reference that constant.
  final bool? peopleTagsEnabled;

  @override
  Widget wrappedRoute(BuildContext context) => this;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Debug is a hidden entry: a long press on the version line reveals it
  /// for this visit only.
  bool _isDebugRevealed = false;

  Future<void> _confirmResetLocal(BuildContext context) async {
    final l10n = L10n.of(context)!;
    final cubit = GetIt.I<SettingsCubit>();
    final seedWarning = await cubit.hasSeedOnlyLocalAccounts();
    if (!context.mounted) return;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.authRecoveryResetLocalTitle,
      content: seedWarning
          ? '${l10n.authRecoveryResetLocalBody}\n\n'
                '${l10n.authRecoveryResetSeedWarning}'
          : l10n.authRecoveryResetLocalBody,
      confirmLabel: l10n.authRecoveryResetLocalTitle,
      cancelLabel: l10n.buttonCancel,
    );
    if ((confirmed ?? false) && context.mounted) {
      await cubit.resetLocalAuthState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = GetIt.I<SettingsCubit>();
    final authCubit = GetIt.I<AuthCubit>();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final visibleVersion = cubit.state.visibleVersion;
    return HomeRailFrame(
      selectedTab: HomeTab.me,
      child: Scaffold(
        appBar: TenturaTopBar.of(
          context,
          leading: const AutoLeadingWithFallback(fallbackPath: kPathProfile),
          title: Text(l10n.labelSettings),
          progress: BlocSelector<AuthCubit, AuthState, bool>(
            bloc: authCubit,
            selector: (state) => state.isLoading,
            builder: TenturaTopBar.loadingBar,
          ),
        ),
        body: SafeArea(
          child: TenturaContentColumn(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(tt.screenHPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: tt.sectionGap,
                children: [
                  _LabelledControl(
                    label: l10n.labelLanguage,
                    child: const LanguageSwitchButton(),
                  ),
                  _LabelledControl(
                    label: l10n.labelTheme,
                    child: const ThemeSwitchButton(),
                  ),
                  _SettingsCommandList(
                    l10n: l10n,
                    authCubit: authCubit,
                    settingsCubit: cubit,
                    isDebugRevealed: _isDebugRevealed,
                    peopleTagsEnabled: widget.peopleTagsEnabled ?? kPeopleTagsEnabled,
                    onConfirmResetLocal: () => _confirmResetLocal(context),
                  ),
                  if (visibleVersion != null && visibleVersion.isNotEmpty)
                    Center(
                      child: GestureDetector(
                        onLongPress: () =>
                            setState(() => _isDebugRevealed = true),
                        child: TenturaMetaText(
                          visibleVersion,
                          maxLines: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCommandList extends StatelessWidget {
  const _SettingsCommandList({
    required this.l10n,
    required this.authCubit,
    required this.settingsCubit,
    required this.isDebugRevealed,
    required this.peopleTagsEnabled,
    required this.onConfirmResetLocal,
  });

  final L10n l10n;
  final AuthCubit authCubit;
  final SettingsCubit settingsCubit;
  final bool isDebugRevealed;
  final bool peopleTagsEnabled;
  final VoidCallback onConfirmResetLocal;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return BlocSelector<AuthCubit, AuthState, bool>(
      bloc: authCubit,
      selector: (state) => state.isLoading,
      builder: (context, isLoading) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: tt.sectionGap,
          children: [
            TenturaMenuGroup(
              title: l10n.settingsSectionAccount,
              children: [
                FutureBuilder<String?>(
                  future: settingsCubit.tryGetCurrentAccountSeed(),
                  builder: (context, snapshot) {
                    final seed = snapshot.data;
                    if (seed == null || seed.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return TenturaMenuTile(
                      icon: Icons.remove_red_eye_outlined,
                      title: l10n.showSeed,
                      onTap: () async {
                        if (context.mounted) {
                          await ShowSeedDialog.show(context, seed: seed);
                        }
                      },
                    );
                  },
                ),
                TenturaMenuTile(
                  icon: Icons.key_outlined,
                  title: l10n.signInMethods,
                  onTap: () => context.router.push(CredentialsRoute()),
                ),
                TenturaMenuTile(
                  icon: Icons.notifications_outlined,
                  title: l10n.notificationSettings,
                  onTap: () =>
                      context.router.push(const NotificationSettingsRoute()),
                ),
                TenturaMenuTile(
                  icon: Icons.alt_route_outlined,
                  title: l10n.settingsRoutingMute,
                  onTap: () => context.router.push(const RoutingMuteRoute()),
                ),
                if (peopleTagsEnabled)
                  TenturaMenuTile(
                    key: const Key('settings.people_tags'),
                    icon: Icons.sell_outlined,
                    title: l10n.peopleTagsScreenTitle,
                    onTap: () => context.router.push(const PeopleTagsRoute()),
                  ),
                const NoisyWallTile(),
              ],
            ),
            TenturaMenuGroup(
              title: l10n.settingsSectionApp,
              children: [
                TenturaMenuTile(
                  icon: Icons.help_outline,
                  title: l10n.orientationReopen,
                  onTap: () => showHowTenturaWorksSheet(context),
                ),
                if (!kIsWeb)
                  TenturaMenuTile(
                    icon: Icons.reset_tv,
                    title: l10n.showIntroAgain,
                    opensPage: false,
                    onTap: () => settingsCubit.setIntroEnabled(true),
                  ),
                const ResetCountersButton(),
                if (isDebugRevealed)
                  TenturaMenuTile(
                    icon: Icons.bug_report_outlined,
                    title: l10n.settingsDebug,
                    onTap: () =>
                        context.router.push(const DebugSettingsRoute()),
                  ),
              ],
            ),
            TenturaMenuGroup(
              title: l10n.settingsSectionDanger,
              children: [
                TenturaMenuTile(
                  icon: Icons.delete_forever_outlined,
                  title: l10n.authRecoveryResetLocalTitle,
                  destructive: true,
                  onTap: isLoading ? null : onConfirmResetLocal,
                ),
                TenturaMenuTile(
                  icon: Icons.person_off_outlined,
                  title: l10n.settingsRequestProfileDeletion,
                  destructive: true,
                  onTap: isLoading
                      ? null
                      : () => MyProfileDeleteDialog.show(context),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A segmented setting under its own section label, on the menu keyline.
class _LabelledControl extends StatelessWidget {
  const _LabelledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: tt.menuIconStart),
          child: TenturaSectionHeader(label: label),
        ),
        child,
      ],
    );
  }
}
