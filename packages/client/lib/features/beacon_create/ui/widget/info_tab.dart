import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/schedule_date_format.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/unfocus_sheet_body.dart';
import 'package:tentura/ui/widget/beacon_requirements_bar.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import 'package:tentura/features/beacon/ui/widget/beacon_lineage_parent_link.dart';
import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/context/ui/widget/context_drop_down.dart';
import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';

import '../bloc/beacon_create_cubit.dart';
import '../screen/beacon_icon_picker_screen.dart';

class InfoTab extends StatefulWidget {
  const InfoTab({super.key});

  @override
  State<InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<InfoTab> with StringInputValidator {
  late final _l10n = L10n.of(context)!;

  late final _theme = Theme.of(context);

  late final _cubit = context.read<BeaconCreateCubit>();

  /// Declared timing meaning (event / deadline / none). Held locally so the user
  /// can pick a mode before choosing a date; initialized from existing dates so
  /// editing preselects the right mode.
  late BeaconScheduleKind _timingKind = _deriveTimingKind(
    _cubit.state.startAt,
    _cubit.state.endAt,
  );

  late final _locationController = TextEditingController(
    text: _cubit.state.location,
  );

  late final _needSummaryController = TextEditingController(
    text: _cubit.state.needSummary,
  );

  late final _successCriteriaController = TextEditingController(
    text: _cubit.state.successCriteria,
  );

  @override
  void dispose() {
    _locationController.dispose();
    _needSummaryController.dispose();
    _successCriteriaController.dispose();
    super.dispose();
  }

  Future<void> _showRequirementsSheet(BuildContext context) async {
    final l10n = L10n.of(context)!;
    var selected = Set<String>.from(_cubit.state.needs);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => UnfocusSheetBody(
        child: StatefulBuilder(
          builder: (ctx, setModalState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.beaconRequirementsTitle,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton(
                      onPressed: () {
                        _cubit.setNeeds(selected);
                        Navigator.of(ctx).pop();
                      },
                      child: Text(l10n.buttonSave),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    CapabilityChipSet(
                      selectedSlugs: selected,
                      onChanged: (s) => setModalState(() => selected = s),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<BeaconCreateCubit, BeaconCreateState>(
        bloc: _cubit,
        listenWhen: (prev, curr) =>
            prev.location != curr.location ||
            prev.needSummary != curr.needSummary ||
            prev.successCriteria != curr.successCriteria,
        listener: (context, state) {
          if (_locationController.text != state.location) {
            _locationController.text = state.location;
          }
          if (_needSummaryController.text != state.needSummary) {
            _needSummaryController.text = state.needSummary;
          }
          if (_successCriteriaController.text != state.successCriteria) {
            _successCriteriaController.text = state.successCriteria;
          }
        },
        child: ListView(
          children: [
            BlocSelector<BeaconCreateCubit, BeaconCreateState, String?>(
              bloc: _cubit,
              selector: (s) => s.lineageParentBeaconId,
              builder: (context, parentId) {
                if (parentId == null || parentId.isEmpty) {
                  return const SizedBox.shrink();
                }
                return BeaconLineageParentLink(parentBeaconId: parentId);
              },
            ),
            // Title
            TextFormField(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                hintText: _l10n.beaconTitleRequired,
              ),
              keyboardType: TextInputType.text,
              maxLength: kTitleMaxLength,
              initialValue: _cubit.state.title,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: _cubit.setTitle,
              validator: (text) => titleValidator(_l10n, text),
            ),

            // Description
            TextFormField(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                hintText: _l10n.labelDescription,
              ),
              keyboardType: TextInputType.multiline,
              maxLength: kDescriptionMaxLength,
              maxLines: null,
              initialValue: _cubit.state.description,
              onChanged: _cubit.setDescription,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              validator: (text) => descriptionValidator(_l10n, text),
            ),

            // Need summary & success criteria (need-first; publish enforces min length)
            Padding(
              padding: kPaddingSmallV,
              child: Text(
                _l10n.beaconNeedSummaryTitle,
                style: _theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextFormField(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              controller: _needSummaryController,
              decoration: InputDecoration(
                labelText: _l10n.beaconNeedSummaryFieldLabel,
                helperText: _l10n.beaconNeedSummaryHelper,
              ),
              keyboardType: TextInputType.multiline,
              maxLines: null,
              maxLength: BeaconCreateCubit.kNeedSummaryHardMax,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: _cubit.setNeedSummary,
              validator: (text) {
                final raw = text ?? '';
                if (raw.length > BeaconCreateCubit.kNeedSummaryHardMax) {
                  return _l10n.beaconNeedSummaryTooLongError;
                }
                final t = raw.trim();
                if (t.isNotEmpty &&
                    t.length < BeaconCreateCubit.kNeedSummaryPublishMin) {
                  return _l10n.beaconNeedSummaryTooShortError;
                }
                return null;
              },
            ),
            Padding(
              padding: kPaddingSmallV,
              child: TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: _successCriteriaController,
                decoration: InputDecoration(
                  labelText: _l10n.beaconSuccessCriteriaFieldLabel,
                ),
                keyboardType: TextInputType.multiline,
                maxLines: null,
                maxLength: BeaconCreateCubit.kSuccessCriteriaHardMax,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onChanged: _cubit.setSuccessCriteria,
                validator: (text) {
                  final raw = text ?? '';
                  if (raw.length > BeaconCreateCubit.kSuccessCriteriaHardMax) {
                    return _l10n.beaconSuccessCriteriaTooLongError;
                  }
                  return null;
                },
              ),
            ),

            // Requirements — same bottom sheet pattern as forward “Why?” picker
            Padding(
              padding: kPaddingSmallV,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => unawaited(_showRequirementsSheet(context)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _l10n.beaconRequirementsTitle,
                                style: _theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              BlocSelector<
                                BeaconCreateCubit,
                                BeaconCreateState,
                                Set<String>
                              >(
                                bloc: _cubit,
                                selector: (state) => state.needs,
                                builder: (context, needs) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _l10n.beaconRequirementsSelectedCount(
                                        needs.length,
                                      ),
                                      style: _theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: _theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (needs.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      BeaconRequirementsBar(
                                        needs: needs,
                                        maxIcons: 12,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: _theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Context (topics selector; gated — see kShowBeaconCreateContextSelector)
            if (kShowBeaconCreateContextSelector)
              const Padding(
                padding: kPaddingSmallV,
                child: ContextDropDown(),
              ),

            // Timing — declare the meaning of the dates first (event vs
            // deadline), then pick. This is where date ambiguity is removed.
            Padding(
              padding: kPaddingSmallV,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _l10n.beaconTimingWhenTitle,
                    style: _theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<BeaconScheduleKind>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: BeaconScheduleKind.deadline,
                          label: Text(_l10n.beaconTimingDeadline),
                        ),
                        ButtonSegment(
                          value: BeaconScheduleKind.event,
                          label: Text(_l10n.beaconTimingEvent),
                        ),
                        ButtonSegment(
                          value: BeaconScheduleKind.none,
                          label: Text(_l10n.beaconTimingNone),
                        ),
                      ],
                      selected: {_timingKind},
                      onSelectionChanged: (s) => _onTimingKindChanged(s.first),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timingKindHint(_timingKind),
                    style: _theme.textTheme.bodySmall?.copyWith(
                      color: _theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_timingKind != BeaconScheduleKind.none)
                    Padding(
                      padding: kPaddingSmallT,
                      child: BlocSelector<BeaconCreateCubit, BeaconCreateState,
                          String>(
                        bloc: _cubit,
                        selector: _timingSummary,
                        builder: (_, displayText) => _pickerField(
                          key: const Key('BeaconCreate.TimingField'),
                          hint: _l10n.beaconTimingPickDate,
                          displayText: displayText,
                          suffixIcon: const Icon(TenturaIcons.calendar),
                          onTap: () => unawaited(
                            _timingKind == BeaconScheduleKind.deadline
                                ? _pickDeadline(context)
                                : _pickEventDates(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Beacon symbol (optional identity tile)
            Padding(
              padding: kPaddingSmallV,
              child: Text(
                _l10n.beaconSymbolTitle,
                style: _theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
              bloc: _cubit,
              builder: (_, state) {
                final now = DateTime.timestamp();
                final preview = Beacon(
                  createdAt: now,
                  updatedAt: now,
                  title: state.title,
                  iconCode: state.iconCode,
                  iconBackground: state.iconBackground,
                );
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final r = await BeaconIconPickerScreen.show(
                        context,
                        iconCode: state.iconCode,
                        iconBackground: state.iconBackground,
                      );
                      if (!context.mounted || r == null) {
                        return;
                      }
                      if (r.iconCode == null || r.iconCode!.isEmpty) {
                        _cubit.clearBeaconIdentity();
                      } else {
                        _cubit.setIconCode(r.iconCode!);
                        if (r.iconBackground != null) {
                          _cubit.setIconBackground(r.iconBackground);
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          BeaconIdentityTile(beacon: preview, size: 56),
                          const SizedBox(width: kSpacingSmall),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _l10n.beaconSymbolSelectHint,
                                  style: _theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _l10n.beaconSymbolHint,
                                  style: _theme.textTheme.bodySmall?.copyWith(
                                    color: _theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: _theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Location
            Padding(
              padding: kPaddingSmallV,
              child: BlocSelector<BeaconCreateCubit, BeaconCreateState,
                  ({String location, Coordinates? coordinates})>(
                bloc: _cubit,
                selector: (s) =>
                    (location: s.location, coordinates: s.coordinates),
                builder: (_, data) => _pickerField(
                  key: const Key('BeaconCreate.LocationField'),
                  hint: _l10n.addLocation,
                  displayText: data.location,
                  suffixIcon: data.coordinates == null
                      ? const Icon(TenturaIcons.location)
                      : IconButton(
                          key: const Key('BeaconCreate.LocationClearButton'),
                          icon: const Icon(Icons.cancel_rounded),
                          onPressed: () {
                            _locationController.clear();
                            _cubit.setLocation(null, '');
                          },
                        ),
                  onTap: () => unawaited(_pickLocation(context)),
                ),
              ),
            ),
          ],
        ),
      );

  /// Picker row styled like a [TextFormField] but opened via [InkWell], not
  /// `readOnly` + `onTap` on a real text input.
  ///
  /// Workaround: read-only [TextFormField] inside a [ListView] often does not
  /// receive taps on Flutter web (especially mobile Firefox); [onTap] never
  /// runs so date/map dialogs never open. See flutter/flutter#164282.
  Widget _pickerField({
    required Key key,
    required String hint,
    required String displayText,
    required Widget? suffixIcon,
    required VoidCallback onTap,
  }) =>
      InputDecorator(
        key: key,
        decoration: InputDecoration(
          hintText: hint,
          suffixIcon: suffixIcon,
        ),
        isEmpty: displayText.isEmpty,
        child: InkWell(
          onTap: onTap,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              displayText,
              style: _theme.textTheme.bodyLarge,
            ),
          ),
        ),
      );

  /// Deadline mode: one date → `endAt` only (startAt cleared).
  Future<void> _pickDeadline(BuildContext context) async {
    final now = DateTime.timestamp();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      currentDate: now,
      initialDate: _cubit.state.endAt,
      lastDate: now.add(const Duration(days: 365)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) {
      _cubit.setDeadline(picked);
    }
  }

  /// Event mode: a date or period. Same start/end day → single-moment event
  /// (`startAt` only); a span → window (`startAt` + `endAt`).
  Future<void> _pickEventDates(BuildContext context) async {
    final now = DateTime.timestamp();
    final dateRange = await showDateRangePicker(
      context: context,
      firstDate: now,
      currentDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      saveText: _l10n.buttonOk,
    );
    if (dateRange != null) {
      final sameDay = dateRange.start.year == dateRange.end.year &&
          dateRange.start.month == dateRange.end.month &&
          dateRange.start.day == dateRange.end.day;
      _cubit.setEventDates(
        startAt: dateRange.start,
        endAt: sameDay ? null : dateRange.end,
      );
    }
  }

  Future<void> _pickLocation(BuildContext context) async {
    final location = await ChooseLocationDialog.show(
      context,
      center: _cubit.state.coordinates,
    );
    if (location != null) {
      final locationName =
          location.place?.toString() ?? location.coords.toString();

      _locationController.text = locationName;
      _cubit.setLocation(location.coords, locationName);
    }
  }

  static BeaconScheduleKind _deriveTimingKind(DateTime? start, DateTime? end) =>
      start != null
      ? BeaconScheduleKind.event
      : (end != null ? BeaconScheduleKind.deadline : BeaconScheduleKind.none);

  String _timingKindHint(BeaconScheduleKind kind) => switch (kind) {
    BeaconScheduleKind.deadline => _l10n.beaconTimingDeadlineHint,
    BeaconScheduleKind.event => _l10n.beaconTimingEventHint,
    BeaconScheduleKind.none => _l10n.beaconTimingNoneHint,
  };

  /// Human summary of the chosen dates, reusing the same formatters the card
  /// uses so authoring and display speak one language.
  String _timingSummary(BeaconCreateState s) {
    final now = DateTime.now();
    final locale = _l10n.localeName;
    if (s.startAt != null && s.endAt != null) {
      return formatScheduleRange(
        s.startAt!,
        s.endAt!,
        localeName: locale,
        now: now,
      );
    }
    if (s.startAt != null) {
      return formatScheduleDate(s.startAt!, localeName: locale, now: now);
    }
    if (s.endAt != null) {
      return _l10n.beaconCardScheduleDeadlineBy(
        formatScheduleDate(s.endAt!, localeName: locale, now: now),
      );
    }
    return '';
  }

  /// Switching mode clears the field that doesn't belong to the new kind so a
  /// stale date can't leak into the wrong semantics; compatible dates are
  /// reinterpreted rather than lost.
  void _onTimingKindChanged(BeaconScheduleKind kind) {
    setState(() => _timingKind = kind);
    final s = _cubit.state;
    switch (kind) {
      case BeaconScheduleKind.none:
        _cubit.clearTiming();
      case BeaconScheduleKind.deadline:
        // Keep an existing end (window end) as the deadline; drop the start.
        _cubit.setDeadline(s.endAt);
      case BeaconScheduleKind.event:
        // Promote a bare deadline date to a single-day event.
        if (s.startAt == null && s.endAt != null) {
          _cubit.setEventDates(startAt: s.endAt!);
        }
    }
  }
}
