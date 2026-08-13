import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura_root/domain/enums.dart';

import '../bloc/profile_cubit.dart';

/// Local calendar midnight for [showDatePicker] bounds (y/m/d only; not `toLocal()` on availability).
@visibleForTesting
DateTime availabilityPickerLocalDate(DateTime utcCalendarDate) =>
    DateTime(utcCalendarDate.year, utcCalendarDate.month, utcCalendarDate.day);

Future<void> showAvailabilitySheet(
  BuildContext context, {
  ProfileCubit? profileCubit,
  DateTime Function()? clock,
}) {
  final cubit = profileCubit ?? GetIt.I<ProfileCubit>();
  return showTenturaAdaptiveSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => AvailabilitySheetBody(
      profileCubit: cubit,
      clock: clock,
    ),
  );
}

/// Sheet body — exposed for widget tests via [showAvailabilitySheet].
class AvailabilitySheetBody extends StatefulWidget {
  const AvailabilitySheetBody({
    required this.profileCubit,
    this.clock,
    super.key,
  });

  final ProfileCubit profileCubit;
  final DateTime Function()? clock;

  @override
  State<AvailabilitySheetBody> createState() => _AvailabilitySheetBodyState();
}

class _AvailabilitySheetBodyState extends State<AvailabilitySheetBody> {
  DateTime? _selectedResumeOn;
  bool _localLimitedInFlight = false;
  bool _localPauseInFlight = false;
  bool _localResumeInFlight = false;

  ProfileCubit get _cubit => widget.profileCubit;

  DateTime get _todayUtc => availabilityTodayUtc(widget.clock);

  bool get _isPaused =>
      _cubit.state.profile.availability.effectiveOn(_todayUtc) ==
      AvailabilityView.paused;

  Future<void> _onLimitedChanged(bool value) async {
    if (_localLimitedInFlight || _cubit.isAvailabilityLimitedInFlight) return;
    setState(() => _localLimitedInFlight = true);
    try {
      await _cubit.setAvailabilityLimited(value);
    } finally {
      if (mounted) setState(() => _localLimitedInFlight = false);
    }
  }

  void _selectPreset(DateTime resumeOn) {
    setState(() => _selectedResumeOn = resumeOn);
  }

  Future<void> _pickDate() async {
    if (_localPauseInFlight || _cubit.isAvailabilityPauseInFlight) return;
    final l10n = L10n.of(context)!;
    final tomorrowUtc = availabilityTomorrowPreset(_todayUtc);
    final maxUtc = availabilityMaxResumeOn(_todayUtc);
    final picked = await showDatePicker(
      context: context,
      helpText: l10n.availabilityDatePickerTitle,
      initialDate: availabilityPickerLocalDate(tomorrowUtc),
      firstDate: availabilityPickerLocalDate(tomorrowUtc),
      lastDate: availabilityPickerLocalDate(maxUtc),
    );
    if (!mounted || picked == null) return;
    setState(
      () => _selectedResumeOn = utcCalendarDateFromLocalPicker(picked),
    );
  }

  Future<void> _onPausePressed() async {
    final resumeOn = _selectedResumeOn;
    if (resumeOn == null ||
        _localPauseInFlight ||
        _cubit.isAvailabilityPauseInFlight) {
      return;
    }
    setState(() => _localPauseInFlight = true);
    try {
      await _cubit.pauseAvailability(resumeOn);
      if (!mounted) return;
      final profile = _cubit.state.profile;
      if (profile.availability.effectiveOn(_todayUtc) ==
              AvailabilityView.paused &&
          profile.availability.resumeOn == resumeOn) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _localPauseInFlight = false);
    }
  }

  Future<void> _onResumePressed() async {
    if (_localResumeInFlight || _cubit.isAvailabilityResumeInFlight) return;
    setState(() => _localResumeInFlight = true);
    try {
      await _cubit.resumeAvailability();
      if (!mounted) return;
      if (_cubit.state.profile.availability.effectiveOn(_todayUtc) !=
          AvailabilityView.paused) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _localResumeInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final tt = context.tt;

    return BlocBuilder<ProfileCubit, ProfileState>(
      bloc: _cubit,
      builder: (context, state) {
        final availability = state.profile.availability;
        final limitedInFlight =
            _localLimitedInFlight || _cubit.isAvailabilityLimitedInFlight;
        final pauseInFlight =
            _localPauseInFlight || _cubit.isAvailabilityPauseInFlight;
        final resumeInFlight =
            _localResumeInFlight || _cubit.isAvailabilityResumeInFlight;
        final selectedResumeOn = _selectedResumeOn;
        final echoWhen = selectedResumeOn == null
            ? null
            : availabilityWhenLabel(l10n, selectedResumeOn, _todayUtc);

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              tt.screenHPadding,
              tt.rowGap,
              tt.screenHPadding,
              tt.sectionGap + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.availabilitySheetTitle,
                  style: textTheme.titleMedium,
                ),
                SizedBox(height: tt.sectionGap),
                SwitchListTile(
                  key: const Key('availability_limited_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.availabilityLimitedSwitchTitle),
                  subtitle: Text(l10n.availabilityLimitedSwitchDescription),
                  value: availability.isLimited,
                  onChanged: limitedInFlight ? null : _onLimitedChanged,
                ),
                SizedBox(height: tt.sectionGap),
                const TenturaHairlineDivider(),
                SizedBox(height: tt.sectionGap),
                Text(
                  l10n.availabilityPauseSectionTitle,
                  style: textTheme.titleSmall,
                ),
                SizedBox(height: tt.rowGap),
                Text(
                  l10n.availabilityPauseSectionDescription,
                  style: textTheme.bodyMedium,
                ),
                SizedBox(height: tt.sectionGap),
                Wrap(
                  spacing: tt.rowGap,
                  runSpacing: tt.rowGap,
                  children: [
                    _PresetButton(
                      key: const Key('availability_preset_tomorrow'),
                      label: l10n.availabilityPresetTomorrow,
                      onPressed: pauseInFlight
                          ? null
                          : () => _selectPreset(
                              availabilityTomorrowPreset(_todayUtc),
                            ),
                    ),
                    _PresetButton(
                      key: const Key('availability_preset_weekend'),
                      label: l10n.availabilityPresetThisWeekend,
                      onPressed: pauseInFlight
                          ? null
                          : () => _selectPreset(
                              availabilityThisWeekendPreset(_todayUtc),
                            ),
                    ),
                    _PresetButton(
                      key: const Key('availability_preset_one_week'),
                      label: l10n.availabilityPresetOneWeek,
                      onPressed: pauseInFlight
                          ? null
                          : () => _selectPreset(
                              availabilityOneWeekPreset(_todayUtc),
                            ),
                    ),
                    _PresetButton(
                      key: const Key('availability_preset_one_month'),
                      label: l10n.availabilityPresetOneMonth,
                      onPressed: pauseInFlight
                          ? null
                          : () => _selectPreset(
                              availabilityOneMonthPreset(_todayUtc),
                            ),
                    ),
                    _PresetButton(
                      key: const Key('availability_preset_pick_date'),
                      label: l10n.availabilityPresetPickDate,
                      onPressed: pauseInFlight ? null : _pickDate,
                    ),
                  ],
                ),
                if (echoWhen != null) ...[
                  SizedBox(height: tt.sectionGap),
                  TenturaStatusText(
                    l10n.availabilityResumeEcho(echoWhen),
                    tone: TenturaTone.neutral,
                    maxLines: null,
                    softWrap: true,
                  ),
                ],
                SizedBox(height: tt.sectionGap),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const Key('availability_pause_button'),
                    onPressed: selectedResumeOn == null || pauseInFlight
                        ? null
                        : _onPausePressed,
                    child: Text(l10n.availabilityPauseAction),
                  ),
                ),
                if (_isPaused) ...[
                  SizedBox(height: tt.sectionGap),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TenturaTextAction(
                      key: const Key('availability_resume_now'),
                      label: l10n.availabilityResumeNow,
                      onPressed: resumeInFlight ? null : _onResumePressed,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, tt.buttonHeight),
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.rowGap,
        ),
      ),
      child: Text(label),
    );
  }
}
