import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/notification_settings.dart';
import '../bloc/notification_settings_cubit.dart';

@RoutePage()
class NotificationSettingsScreen extends StatelessWidget
    implements AutoRouteWrapper {
  const NotificationSettingsScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = NotificationSettingsCubit();
      unawaited(cubit.fetch());
      return cubit;
    },
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: Text(l10n.notificationSettings),
      ),
      body: BlocBuilder<NotificationSettingsCubit, NotificationSettingsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final cubit = context.read<NotificationSettingsCubit>();
          final s = state.settings;
          return TenturaContentColumn(
            child: ListView(
              children: [
                _SectionHeader(label: l10n.notificationSettingsPush),
                for (final c in NotificationSettingsCategory.values)
                  SwitchListTile(
                    title: Text(_categoryLabel(l10n, c)),
                    subtitle: Text(_categoryDesc(l10n, c)),
                    value: s.isEnabled(c, email: false),
                    onChanged: (v) => cubit.setChannelCategory(
                      category: c,
                      email: false,
                      enabled: v,
                    ),
                  ),
                const TenturaHairlineDivider(),
                _SectionHeader(label: l10n.notificationSettingsEmail),
                for (final c in NotificationSettingsCategory.values)
                  SwitchListTile(
                    title: Text(_categoryLabel(l10n, c)),
                    value: s.isEnabled(c, email: true),
                    onChanged: (v) => cubit.setChannelCategory(
                      category: c,
                      email: true,
                      enabled: v,
                    ),
                  ),
                const TenturaHairlineDivider(),
                _SectionHeader(label: l10n.notificationSettingsInApp),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.tt.screenHPadding,
                  ),
                  child: Text(
                    l10n.notificationSettingsInAppMandatory,
                    style: TenturaText.bodySmall(context.tt.textMuted),
                  ),
                ),
                for (final value in InAppNotificationClass.values)
                  SwitchListTile(
                    title: Text(_inAppLabel(l10n, value)),
                    subtitle: Text(_inAppDescription(l10n, value)),
                    value: !s.mutedInAppEventClasses.contains(value),
                    onChanged: (enabled) => cubit.setInAppClass(
                      value: value,
                      muted: !enabled,
                    ),
                  ),
                const TenturaHairlineDivider(),
                _SectionHeader(label: l10n.notificationDigest),
                RadioGroup<NotificationDigestCadence>(
                  groupValue: s.emailDigest,
                  onChanged: (v) => v == null ? null : cubit.setDigest(v),
                  child: Column(
                    children: [
                      for (final cadence in NotificationDigestCadence.values)
                        RadioListTile<NotificationDigestCadence>(
                          title: Text(_digestLabel(l10n, cadence)),
                          value: cadence,
                        ),
                    ],
                  ),
                ),
                const TenturaHairlineDivider(),
                _SectionHeader(label: l10n.notificationQuietHours),
                _QuietHoursControls(settings: s),
                const TenturaHairlineDivider(),
                SwitchListTile(
                  title: Text(l10n.notificationLockScreen),
                  subtitle: Text(l10n.notificationLockScreenDesc),
                  value: s.lockScreenSafe,
                  onChanged: cubit.setLockScreenSafe,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _categoryLabel(
    L10n l10n,
    NotificationSettingsCategory c,
  ) => switch (c) {
    NotificationSettingsCategory.asksOfMe => l10n.notificationCatAsksOfMe,
    NotificationSettingsCategory.unblocksMe => l10n.notificationCatUnblocksMe,
    NotificationSettingsCategory.coordination =>
      l10n.notificationCatCoordination,
    NotificationSettingsCategory.connections => l10n.notificationCatConnections,
    NotificationSettingsCategory.ambient => l10n.notificationCatAmbient,
  };

  static String _categoryDesc(L10n l10n, NotificationSettingsCategory c) =>
      switch (c) {
        NotificationSettingsCategory.asksOfMe =>
          l10n.notificationCatAsksOfMeDesc,
        NotificationSettingsCategory.unblocksMe =>
          l10n.notificationCatUnblocksMeDesc,
        NotificationSettingsCategory.coordination =>
          l10n.notificationCatCoordinationDesc,
        NotificationSettingsCategory.connections =>
          l10n.notificationCatConnectionsDesc,
        NotificationSettingsCategory.ambient => l10n.notificationCatAmbientDesc,
      };

  static String _digestLabel(L10n l10n, NotificationDigestCadence c) =>
      switch (c) {
        NotificationDigestCadence.off => l10n.notificationDigestOff,
        NotificationDigestCadence.daily => l10n.notificationDigestDaily,
        NotificationDigestCadence.weekly => l10n.notificationDigestWeekly,
      };

  static String _inAppLabel(L10n l10n, InAppNotificationClass value) =>
      switch (value) {
        InAppNotificationClass.coordinationChurn =>
          l10n.notificationSettingsInAppCoordination,
        InAppNotificationClass.requestProgress =>
          l10n.notificationSettingsInAppRequestProgress,
      };

  static String _inAppDescription(L10n l10n, InAppNotificationClass value) =>
      switch (value) {
        InAppNotificationClass.coordinationChurn =>
          l10n.notificationSettingsInAppCoordinationDesc,
        InAppNotificationClass.requestProgress =>
          l10n.notificationSettingsInAppRequestProgressDesc,
      };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.sectionGap,
        tt.screenHPadding,
        tt.tightGap,
      ),
      child: Text(
        label.toUpperCase(),
        style: TenturaText.typeLabel(context.tt.textMuted),
      ),
    );
  }
}

class _QuietHoursControls extends StatelessWidget {
  const _QuietHoursControls({required this.settings});

  final NotificationSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<NotificationSettingsCubit>();
    return Column(
      children: [
        SwitchListTile(
          title: Text(l10n.notificationQuietHoursEnable),
          value: settings.hasQuietHours,
          onChanged: (v) => unawaited(
            v
                // Default 22:00 → 07:00 local.
                ? cubit.setQuietHours(startMinute: 22 * 60, endMinute: 7 * 60)
                : cubit.clearQuietHours(),
          ),
        ),
        if (settings.hasQuietHours) ...[
          ListTile(
            title: Text(l10n.notificationQuietHoursFrom),
            trailing: Text(_fmt(settings.quietHoursStart!)),
            onTap: () => _pick(context, isStart: true),
          ),
          ListTile(
            title: Text(l10n.notificationQuietHoursTo),
            trailing: Text(_fmt(settings.quietHoursEnd!)),
            onTap: () => _pick(context, isStart: false),
          ),
        ],
      ],
    );
  }

  Future<void> _pick(BuildContext context, {required bool isStart}) async {
    final cubit = context.read<NotificationSettingsCubit>();
    final current = isStart
        ? settings.quietHoursStart!
        : settings.quietHoursEnd!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) {
      return;
    }
    final minutes = picked.hour * 60 + picked.minute;
    await cubit.setQuietHours(
      startMinute: isStart ? minutes : settings.quietHoursStart!,
      endMinute: isStart ? settings.quietHoursEnd! : minutes,
    );
  }

  static String _fmt(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
