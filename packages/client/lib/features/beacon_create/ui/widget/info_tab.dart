import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/unfocus_sheet_body.dart';
import 'package:tentura/ui/widget/beacon_requirements_bar.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

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

  late final _dateRangeController = TextEditingController(
    text: _formatDateRange(_cubit.state.startAt, _cubit.state.endAt),
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
    _dateRangeController.dispose();
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

            // Date Range
            Padding(
              padding: kPaddingSmallV,
              child: TextFormField(
                readOnly: true,
                controller: _dateRangeController,
                decoration: InputDecoration(
                  hintText: _l10n.setDisplayPeriod,
                  suffixIcon: const Icon(TenturaIcons.calendar),
                ),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onTap: () async {
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
                    _dateRangeController.text = _formatDateRange(
                      dateRange.start,
                      dateRange.end,
                    );
                    _cubit.setDateRange(
                      startAt: dateRange.start,
                      endAt: dateRange.end,
                    );
                  }
                },
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
              child: TextFormField(
                readOnly: true,
                controller: _locationController,
                decoration: InputDecoration(
                  hintText: _l10n.addLocation,
                  suffixIcon:
                      BlocSelector<
                        BeaconCreateCubit,
                        BeaconCreateState,
                        Coordinates?
                      >(
                        bloc: _cubit,
                        selector: (state) => state.coordinates,
                        builder: (_, coordinates) => coordinates == null
                            ? const Icon(TenturaIcons.location)
                            : IconButton(
                                icon: const Icon(Icons.cancel_rounded),
                                onPressed: () {
                                  _locationController.clear();
                                  _cubit.setLocation(null, '');
                                },
                              ),
                      ),
                ),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                onTap: () async {
                  final location = await ChooseLocationDialog.show(
                    context,
                    center: _cubit.state.coordinates,
                  );
                  if (location != null) {
                    final locationName =
                        location.place?.toString() ??
                        location.coords.toString();

                    _locationController.text = locationName;
                    _cubit.setLocation(location.coords, locationName);
                  }
                },
              ),
            ),
          ],
        ),
      );

  String _formatDateRange(DateTime? start, DateTime? end) =>
      start == null || end == null
      ? ''
      : '${dateFormatYMD(start)} - ${dateFormatYMD(end)}';
}
