import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/debug_settings_cubit.dart';

@RoutePage()
class DebugSettingsScreen extends StatelessWidget implements AutoRouteWrapper {
  const DebugSettingsScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (_) {
          final cubit = GetIt.I<DebugSettingsCubit>();
          unawaited(cubit.loadFcmInfo());
          return cubit;
        },
        child: this,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Scaffold(
      appBar: AppBar(
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
                    _FcmRegistrationSection(state: state, l10n: l10n),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: tt.rowGap,
                      children: [
                        TenturaCommandButton(
                          label: l10n.settingsNotificationsTest,
                          icon: const Icon(Icons.notifications_active_outlined),
                          onPressed: state.isFcmTestEnabled
                              ? cubit.sendTestNotification
                              : null,
                        ),
                        TenturaCommandButton(
                          label: l10n.settingsEmailTest,
                          icon: const Icon(Icons.email_outlined),
                          onPressed: state.isEmailTestEnabled
                              ? cubit.sendTestEmail
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
              ? TenturaMetaText(l10n.settingsFcmTokenUnavailable)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: tt.rowGap,
                  children: [
                    SelectableText(token),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: token),
                        ),
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
          child: TenturaMetaText(
            state.permissionGranted
                ? l10n.settingsFcmPermissionGranted
                : l10n.settingsFcmPermissionDenied,
          ),
        ),
        _InfoRow(
          label: l10n.settingsFcmServerSynced,
          child: TenturaMetaText(
            state.serverSynced
                ? l10n.settingsFcmServerSyncedYes
                : l10n.settingsFcmServerSyncedNo,
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
