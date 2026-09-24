import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/copy_text_to_clipboard.dart';

import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';

import '../bloc/debug_settings_cubit.dart';
import '../message/debug_settings_messages.dart';

@RoutePage()
class DebugSettingsScreen extends StatelessWidget implements AutoRouteWrapper {
  const DebugSettingsScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) {
          final cubit = GetIt.I<DebugSettingsCubit>();
          unawaited(cubit.loadFcmInfo());
          return cubit;
        },
      ),
      BlocProvider.value(value: GetIt.I<HomeActivationCubit>()),
    ],
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: Text(l10n.settingsDebug),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.settingsRefresh,
            onPressed: () => context.read<DebugSettingsCubit>().loadFcmInfo(),
          ),
        ],
      ),
      body: SafeArea(
        child: TenturaContentColumn(
          child: BlocBuilder<DebugSettingsCubit, DebugSettingsState>(
            builder: (context, state) {
              if (state.isLoadingFcmInfo) {
                return const Center(child: CircularProgressIndicator());
              }
              final cubit = context.read<DebugSettingsCubit>();
              return SingleChildScrollView(
                padding: EdgeInsets.all(tt.screenHPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: tt.sectionGap,
                  children: [
                    const FirstRunOrientationDebugSection(),
                    _FcmRegistrationSection(state: state, l10n: l10n),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: tt.rowGap,
                      children: [
                        TenturaCommandButton(
                          label: l10n.settingsFcmForceReregister,
                          icon: const Icon(Icons.sync),
                          onPressed: state.isForceReregisterEnabled
                              ? cubit.forceReregisterDevice
                              : null,
                        ),
                        TenturaCommandButton(
                          label: l10n.settingsNotificationsTest,
                          icon: const Icon(Icons.notifications_active_outlined),
                          onPressed: state.isFcmTestEnabled
                              ? cubit.sendTestNotification
                              : null,
                        ),
                        TenturaCommandButton(
                          label: l10n.settingsFcmDirectNotificationTest,
                          icon: const Icon(Icons.phonelink_ring_outlined),
                          onPressed: cubit.testDirectNotification,
                        ),
                        TenturaCommandButton(
                          label: l10n.settingsEmailTest,
                          icon: const Icon(Icons.email_outlined),
                          onPressed: state.isEmailTestEnabled
                              ? cubit.sendTestEmail
                              : null,
                        ),
                        TenturaCommandButton(
                          label: l10n.settingsRecalculateCounters,
                          icon: const Icon(Icons.calculate_outlined),
                          onPressed: state.isRecalculateCountersEnabled
                              ? cubit.recalculateCounters
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// First-run orientation debug controls (plan §7). Public for widget tests.
class FirstRunOrientationDebugSection extends StatelessWidget {
  const FirstRunOrientationDebugSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocBuilder<HomeActivationCubit, HomeActivationState>(
      builder: (context, activationState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: tt.rowGap,
          children: [
            Text(
              l10n.settingsDebugOrientationSection,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              l10n.settingsDebugOrientationStatus(
                activationState.activatedLatch ? 'true' : 'false',
                activationState.dismissedLatch ? 'true' : 'false',
                activationState.signals.activityCount,
              ),
            ),
            SegmentedButton<OrientationDebugOverride>(
              selected: {activationState.debugOverride},
              showSelectedIcon: false,
              segments: [
                ButtonSegment<OrientationDebugOverride>(
                  value: OrientationDebugOverride.auto,
                  label: Text(
                    l10n.settingsDebugOrientationAuto,
                    key: TestIds.key(TestIds.debugOrientationAuto),
                  ),
                ),
                ButtonSegment<OrientationDebugOverride>(
                  value: OrientationDebugOverride.show,
                  label: Text(
                    l10n.settingsDebugOrientationShow,
                    key: TestIds.key(TestIds.debugOrientationShow),
                  ),
                ),
                ButtonSegment<OrientationDebugOverride>(
                  value: OrientationDebugOverride.hide,
                  label: Text(
                    l10n.settingsDebugOrientationHide,
                    key: TestIds.key(TestIds.debugOrientationHide),
                  ),
                ),
              ],
              onSelectionChanged: (selection) {
                unawaited(
                  context.read<HomeActivationCubit>().setDebugOverride(
                    selection.first,
                  ),
                );
              },
            ),
            TenturaCommandButton(
              key: TestIds.key(TestIds.debugOrientationReset),
              label: l10n.settingsDebugOrientationReset,
              onPressed: () async {
                await context.read<HomeActivationCubit>().resetFirstRunState();
                GetIt.I<UiEffectPort>().emit(
                  const ShowMessage(DebugOrientationResetMessage()),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _FcmRegistrationSection extends StatelessWidget {
  const _FcmRegistrationSection({
    required this.state,
    required this.l10n,
  });

  final DebugSettingsState state;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final token = state.fcmToken;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tt.rowGap,
      children: [
        Text(
          l10n.settingsFcmRegistration,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        _InfoRow(
          label: l10n.settingsFcmToken,
          child: token == null || token.isEmpty
              ? TenturaStatusText(
                  l10n.settingsFcmTokenUnavailable,
                  tone: TenturaTone.danger,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: tt.rowGap,
                  children: [
                    SelectableText(token),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          unawaited(copyTextToClipboard(token));
                        },
                        child: Text(l10n.copyToClipboard),
                      ),
                    ),
                  ],
                ),
        ),
        _InfoRow(
          label: l10n.settingsFcmAppId,
          child: SelectableText(state.fcmAppId ?? '—'),
        ),
        _InfoRow(
          label: l10n.settingsFcmPlatform,
          child: TenturaMetaText(state.platform),
        ),
        _InfoRow(
          label: l10n.settingsFcmPermission,
          child: TenturaStatusText(
            state.permissionGranted
                ? l10n.settingsFcmPermissionGranted
                : l10n.settingsFcmPermissionDenied,
            tone: state.permissionGranted
                ? TenturaTone.good
                : TenturaTone.danger,
          ),
        ),
        _InfoRow(
          label: l10n.settingsFcmServerSynced,
          child: TenturaStatusText(
            state.serverSynced
                ? l10n.settingsFcmServerSyncedYes
                : l10n.settingsFcmServerSyncedNo,
            tone: state.serverSynced ? TenturaTone.good : TenturaTone.danger,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tt.rowGap / 2,
      children: [
        TenturaMetaText(label),
        child,
      ],
    );
  }
}
