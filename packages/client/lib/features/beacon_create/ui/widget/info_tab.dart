import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/env.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/schedule_date_format.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/unfocus_sheet_body.dart';
import 'package:tentura/features/capability/ui/widget/removable_capability_chips.dart';

import 'package:tentura/features/capability/ui/widget/capability_chip_set.dart';
import 'package:tentura/features/context/ui/widget/context_drop_down.dart';
import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';

import '../bloc/beacon_create_cubit.dart';
import 'cover_block.dart';
import 'cover_symbol_sheet.dart';
import 'create_optional_summary_row.dart';
import 'image_tab.dart';

class InfoTab extends StatefulWidget {
  const InfoTab({
    this.openImagesInitially = false,
    super.key,
  });

  /// When true (e.g. `?tab=image`), open/focus the Images editor after first frame.
  final bool openImagesInitially;

  @override
  State<InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<InfoTab> with StringInputValidator {
  final _env = GetIt.I<Env>();
  final _imagesSectionKey = GlobalKey();

  late final _l10n = L10n.of(context)!;

  late final _theme = Theme.of(context);

  late final _cubit = context.read<BeaconCreateCubit>();

  /// Declared timing meaning (event / deadline / none). Held locally so the user
  /// can pick a mode before choosing a date; initialized from existing dates so
  /// editing preselects the right mode.
  late final ValueNotifier<BeaconScheduleKind> _timingKindNotifier =
      ValueNotifier(
        _deriveTimingKind(
          _cubit.state.startAt,
          _cubit.state.endAt,
        ),
      );

  late final _titleController = TextEditingController(
    text: _cubit.state.title,
  );

  late final _descriptionController = TextEditingController(
    text: _cubit.state.description,
  );

  late final _locationController = TextEditingController(
    text: _cubit.state.location,
  );

  @override
  void initState() {
    super.initState();
    if (widget.openImagesInitially) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final expanded = context.windowClass == WindowClass.expanded;
        if (expanded) {
          final ctx = _imagesSectionKey.currentContext;
          if (ctx != null) {
            unawaited(
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 200),
                alignment: 0.1,
              ),
            );
          }
        } else {
          unawaited(_showImagesSheet(context));
        }
      });
    }
  }

  @override
  void dispose() {
    _timingKindNotifier.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// Clears primary focus after an overlay route pops so Navigator restoration
  /// cannot leave a non-editing target (e.g. picker InkWell) holding focus on web.
  void _clearFocusAfterOverlay() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Copies in-flight [TextEditingController] text into the cubit so modal sheets
  /// cannot leave draft state behind if focus/IME did not flush
  /// [TextFormField.onChanged] before the overlay opened.
  void _commitFormFieldsToCubit() {
    final s = _cubit.state;
    if (_titleController.text != s.title) {
      _cubit.setTitle(_titleController.text);
    }
    if (_descriptionController.text != s.description) {
      _cubit.setDescription(_descriptionController.text);
    }
  }

  Future<void> _showRequirementsSheet(
    BuildContext context, {
    bool reopenSymbolAfterSave = false,
  }) async {
    _commitFormFieldsToCubit();
    final l10n = L10n.of(context)!;
    final baseline = Set<String>.from(_cubit.state.needs);
    var selected = Set<String>.from(baseline);

    bool hasUnsavedChanges() =>
        baseline.length != selected.length || !baseline.containsAll(selected);

    Future<void> requestClose(BuildContext ctx) async {
      if (!hasUnsavedChanges()) {
        Navigator.of(ctx).pop();
        return;
      }
      final confirmed = await TenturaConfirmDialog.show(
        context: ctx,
        title: l10n.beaconRequirementsDiscardTitle,
        content: l10n.beaconRequirementsDiscardBody,
        confirmLabel: l10n.beaconRequirementsDiscardConfirm,
        cancelLabel: l10n.buttonCancel,
      );
      if ((confirmed ?? false) && ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    }

    await showTenturaAdaptiveSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (_) => UnfocusSheetBody(
        child: StatefulBuilder(
          builder: (ctx, setModalState) {
            final tt = ctx.tt;
            final scheme = Theme.of(ctx).colorScheme;

            void saveAndClose() {
              _commitFormFieldsToCubit();
              final saved = Set<String>.from(selected);
              _cubit.setNeeds(saved);
              Navigator.of(ctx).pop();
              if (reopenSymbolAfterSave && saved.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  unawaited(
                    CoverSymbolSheet.show(
                      context,
                      cubit: _cubit,
                      onManageCapabilities: () => unawaited(
                        _showRequirementsSheet(
                          context,
                          reopenSymbolAfterSave: true,
                        ),
                      ),
                    ),
                  );
                });
              }
            }

            return Focus(
              autofocus: true,
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.escape):
                      _DismissRequirementsSheetIntent(),
                },
                child: Actions(
                  actions: {
                    _DismissRequirementsSheetIntent:
                        CallbackAction<_DismissRequirementsSheetIntent>(
                          onInvoke: (_) {
                            unawaited(requestClose(ctx));
                            return null;
                          },
                        ),
                  },
                  child: PopScope(
                    canPop: !hasUnsavedChanges(),
                    onPopInvokedWithResult: (didPop, _) async {
                      if (didPop) return;
                      await requestClose(ctx);
                    },
                    child: DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.7,
                      minChildSize: 0.4,
                      maxChildSize: 0.95,
                      builder: (_, scrollController) => Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              tt.screenHPadding,
                              tt.sectionGap,
                              tt.screenHPadding,
                              tt.tightGap * 2,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.beaconRequirementsTitle,
                                    style: Theme.of(ctx).textTheme.titleMedium,
                                  ),
                                ),
                                FilledButton(
                                  onPressed: saveAndClose,
                                  child: Text(l10n.buttonSave),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: EdgeInsets.only(
                                left: tt.screenHPadding,
                                right: tt.screenHPadding,
                                bottom: tt.sectionGap * 2,
                              ),
                              children: [
                                Text(
                                  l10n.beaconRequirementsSheetHint,
                                  style: TenturaText.bodySmall(
                                    scheme.onSurfaceVariant,
                                  ),
                                ),
                                SizedBox(height: tt.rowGap),
                                CapabilityChipSet(
                                  selectedSlugs: selected,
                                  onChanged: (s) =>
                                      setModalState(() => selected = s),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showTimingSheet(BuildContext context) async {
    _commitFormFieldsToCubit();
    final l10n = L10n.of(context)!;
    await showTenturaAdaptiveSheet<void>(
      context: context,
      builder: (_) => UnfocusSheetBody(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              context.tt.screenHPadding,
              context.tt.sectionGap,
              context.tt.screenHPadding,
              context.tt.sectionGap,
            ),
            child: ValueListenableBuilder<BeaconScheduleKind>(
              valueListenable: _timingKindNotifier,
              builder: (ctx, timingKind, _) {
                final tt = ctx.tt;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.beaconTimingWhenTitle,
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    SizedBox(height: tt.rowGap),
                    SegmentedButton<BeaconScheduleKind>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: BeaconScheduleKind.deadline,
                          label: Text(l10n.beaconTimingDeadline),
                        ),
                        ButtonSegment(
                          value: BeaconScheduleKind.event,
                          label: Text(l10n.beaconTimingEvent),
                        ),
                        ButtonSegment(
                          value: BeaconScheduleKind.none,
                          label: Text(l10n.beaconTimingNone),
                        ),
                      ],
                      selected: {timingKind},
                      onSelectionChanged: (s) => _onTimingKindChanged(s.first),
                    ),
                    SizedBox(height: tt.tightGap * 2),
                    Text(
                      _timingKindHint(timingKind),
                      style: TenturaText.bodySmall(
                        Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (timingKind != BeaconScheduleKind.none)
                      Padding(
                        padding: EdgeInsets.only(top: tt.rowGap),
                        child:
                            BlocSelector<
                              BeaconCreateCubit,
                              BeaconCreateState,
                              String
                            >(
                              bloc: _cubit,
                              selector: _timingSummary,
                              builder: (_, displayText) => _pickerField(
                                key: const Key('BeaconCreate.TimingField'),
                                hint: l10n.beaconTimingPickDate,
                                displayText: displayText,
                                suffixIcon: const Icon(TenturaIcons.calendar),
                                onTap: () => unawaited(
                                  timingKind == BeaconScheduleKind.deadline
                                      ? _pickDeadline(context)
                                      : _pickEventDates(context),
                                ),
                              ),
                            ),
                      ),
                    SizedBox(height: tt.sectionGap),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(l10n.buttonOk),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showImagesSheet(BuildContext context) async {
    _commitFormFieldsToCubit();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    await showTenturaAdaptiveSheet<void>(
      context: context,
      builder: (_) => UnfocusSheetBody(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (ctx, _) => Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  tt.screenHPadding,
                  tt.sectionGap,
                  tt.screenHPadding,
                  tt.tightGap * 2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.beaconImage,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.buttonOk,
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: BlocProvider<BeaconCreateCubit>.value(
                  value: _cubit,
                  child: const ImageTab(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _createFieldDecoration({
    String? hintText,
    String? labelText,
    String? helperText,
  }) {
    final tt = context.tt;
    return InputDecoration(
      hintText: hintText,
      labelText: labelText,
      helperText: helperText,
      hintStyle: TenturaText.bodyMedium(tt.textMuted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return BlocListener<BeaconCreateCubit, BeaconCreateState>(
      bloc: _cubit,
      listenWhen: (prev, curr) =>
          prev.title != curr.title ||
          prev.description != curr.description ||
          prev.location != curr.location ||
          prev.startAt != curr.startAt ||
          prev.endAt != curr.endAt,
      listener: (context, state) {
        if (_titleController.text != state.title) {
          _titleController.text = state.title;
        }
        if (_descriptionController.text != state.description) {
          _descriptionController.text = state.description;
        }
        if (_locationController.text != state.location) {
          _locationController.text = state.location;
        }
        if (state.startAt != null || state.endAt != null) {
          final derived = _deriveTimingKind(state.startAt, state.endAt);
          if (_timingKindNotifier.value != derived) {
            _timingKindNotifier.value = derived;
          }
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expanded =
              windowClassForWidth(constraints.maxWidth) == WindowClass.expanded;
          return ListView(
            children: [
              Semantics(
                identifier: TestIds.requestTitle,
                textField: true,
                child: TextFormField(
                  key: TestIds.key(TestIds.requestTitle),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _titleController,
                  decoration: _createFieldDecoration(
                    hintText: _l10n.beaconTitleRequired,
                  ),
                  keyboardType: TextInputType.text,
                  maxLength: kBeaconTitleMaxLength,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  onChanged: _cubit.setTitle,
                  onSaved: (value) => _cubit.setTitle(value ?? ''),
                  validator: (text) => beaconTitleValidator(_l10n, text),
                ),
              ),
              Semantics(
                identifier: TestIds.requestDescription,
                textField: true,
                child: TextFormField(
                  key: TestIds.key(TestIds.requestDescription),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  controller: _descriptionController,
                  decoration: _createFieldDecoration(
                    hintText: _l10n.labelDescription,
                  ),
                  keyboardType: TextInputType.multiline,
                  maxLength: kDescriptionMaxLength,
                  maxLines: null,
                  onChanged: _cubit.setDescription,
                  onSaved: (value) => _cubit.setDescription(value ?? ''),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  validator: (text) => beaconDescriptionValidator(_l10n, text),
                ),
              ),
              if (kShowBeaconCreateContextSelector)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: tt.rowGap),
                  child: const ContextDropDown(),
                ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: tt.rowGap),
                child: CoverBlock(
                  onManageCapabilities: () => unawaited(
                    _showRequirementsSheet(
                      context,
                      reopenSymbolAfterSave: true,
                    ),
                  ),
                ),
              ),
              if (expanded)
                ..._expandedOptionalSections(tt)
              else
                ..._compactOptionalSummaryRows(tt),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _compactOptionalSummaryRows(TenturaTokens tt) {
    return [
      Padding(
        padding: EdgeInsets.symmetric(vertical: tt.tightGap),
        child: BlocSelector<BeaconCreateCubit, BeaconCreateState, int>(
          bloc: _cubit,
          selector: (s) => s.needs.length,
          builder: (context, count) => CreateOptionalSummaryRow(
            keyId: const Key('BeaconCreate.RequirementsRow'),
            title: _l10n.beaconRequirementsTitle,
            subtitle: _l10n.beaconRequirementsSelectedCount(count),
            onTap: () => unawaited(_showRequirementsSheet(context)),
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.symmetric(vertical: tt.tightGap),
        child: ValueListenableBuilder<BeaconScheduleKind>(
          valueListenable: _timingKindNotifier,
          builder: (context, timingKind, _) =>
              BlocSelector<BeaconCreateCubit, BeaconCreateState, String>(
                bloc: _cubit,
                selector: _timingSummary,
                builder: (context, summary) {
                  final subtitle = timingKind == BeaconScheduleKind.none
                      ? _l10n.beaconCreateTimingAnytime
                      : (summary.isEmpty
                            ? _l10n.beaconTimingPickDate
                            : summary);
                  return CreateOptionalSummaryRow(
                    keyId: const Key('BeaconCreate.TimingRow'),
                    title: _l10n.beaconTimingWhenTitle,
                    subtitle: subtitle,
                    onTap: () => unawaited(_showTimingSheet(context)),
                  );
                },
              ),
        ),
      ),
      if (_env.isGoogleMapsConfigured)
        Padding(
          padding: EdgeInsets.symmetric(vertical: tt.tightGap),
          child:
              BlocSelector<
                BeaconCreateCubit,
                BeaconCreateState,
                ({String location, Coordinates? coordinates})
              >(
                bloc: _cubit,
                selector: (s) =>
                    (location: s.location, coordinates: s.coordinates),
                builder: (context, data) {
                  final hasCoordinates = data.coordinates != null;
                  final showsUnnamed =
                      hasCoordinates && data.location.trim().isEmpty;
                  final subtitle = !hasCoordinates && data.location.isEmpty
                      ? _l10n.beaconCreatePlaceNone
                      : (showsUnnamed
                            ? _l10n.locationNameUnavailable
                            : data.location);
                  return Row(
                    children: [
                      Expanded(
                        child: CreateOptionalSummaryRow(
                          keyId: const Key('BeaconCreate.LocationRow'),
                          title: _l10n.addLocation,
                          subtitle: subtitle,
                          onTap: () => unawaited(_pickLocation(context)),
                        ),
                      ),
                      if (hasCoordinates)
                        IconButton(
                          key: const Key('BeaconCreate.LocationClearButton'),
                          icon: const Icon(Icons.cancel_rounded),
                          onPressed: () {
                            _locationController.clear();
                            _cubit.setLocation(null, '');
                          },
                        ),
                    ],
                  );
                },
              ),
        ),
      Padding(
        padding: EdgeInsets.symmetric(vertical: tt.tightGap),
        child: BlocSelector<BeaconCreateCubit, BeaconCreateState, int>(
          bloc: _cubit,
          selector: (s) => s.images.length,
          builder: (context, count) => CreateOptionalSummaryRow(
            keyId: const Key('BeaconCreate.ImagesRow'),
            title: _l10n.beaconImage,
            subtitle: count == 0
                ? _l10n.beaconCreateImagesNone
                : _l10n.beaconCreateImagesCount(count),
            onTap: () => unawaited(_showImagesSheet(context)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _expandedOptionalSections(TenturaTokens tt) {
    return [
      Padding(
        padding: EdgeInsets.symmetric(vertical: tt.rowGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlocSelector<BeaconCreateCubit, BeaconCreateState, int>(
              bloc: _cubit,
              selector: (s) => s.needs.length,
              builder: (context, count) => CreateOptionalSummaryRow(
                keyId: const Key('BeaconCreate.RequirementsRow'),
                title: _l10n.beaconRequirementsTitle,
                subtitle: _l10n.beaconRequirementsSelectedCount(count),
                onTap: () => unawaited(_showRequirementsSheet(context)),
              ),
            ),
            BlocSelector<BeaconCreateCubit, BeaconCreateState, Set<String>>(
              bloc: _cubit,
              selector: (state) => state.needs,
              builder: (context, needs) {
                if (needs.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: EdgeInsets.only(top: tt.tightGap),
                  child: RemovableCapabilityChips(
                    slugs: needs,
                    onRemove: _cubit.removeNeed,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.symmetric(vertical: tt.rowGap),
        child: ValueListenableBuilder<BeaconScheduleKind>(
          valueListenable: _timingKindNotifier,
          builder: (context, timingKind, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _l10n.beaconTimingWhenTitle,
                style: _theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: tt.tightGap * 2),
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
                  selected: {timingKind},
                  onSelectionChanged: (s) => _onTimingKindChanged(s.first),
                ),
              ),
              SizedBox(height: tt.tightGap),
              Text(
                _timingKindHint(timingKind),
                style: _theme.textTheme.bodySmall?.copyWith(
                  color: _theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (timingKind != BeaconScheduleKind.none)
                Padding(
                  padding: EdgeInsets.only(top: tt.tightGap * 2),
                  child:
                      BlocSelector<
                        BeaconCreateCubit,
                        BeaconCreateState,
                        String
                      >(
                        bloc: _cubit,
                        selector: _timingSummary,
                        builder: (_, displayText) => _pickerField(
                          key: const Key('BeaconCreate.TimingField'),
                          hint: _l10n.beaconTimingPickDate,
                          displayText: displayText,
                          suffixIcon: const Icon(TenturaIcons.calendar),
                          onTap: () => unawaited(
                            timingKind == BeaconScheduleKind.deadline
                                ? _pickDeadline(context)
                                : _pickEventDates(context),
                          ),
                        ),
                      ),
                ),
            ],
          ),
        ),
      ),
      if (_env.isGoogleMapsConfigured)
        Padding(
          padding: EdgeInsets.symmetric(vertical: tt.rowGap),
          child:
              BlocSelector<
                BeaconCreateCubit,
                BeaconCreateState,
                ({String location, Coordinates? coordinates})
              >(
                bloc: _cubit,
                selector: (s) =>
                    (location: s.location, coordinates: s.coordinates),
                builder: (_, data) {
                  final hasCoordinates = data.coordinates != null;
                  final showsUnnamedPlaceholder =
                      hasCoordinates && data.location.trim().isEmpty;
                  return _pickerField(
                    key: const Key('BeaconCreate.LocationField'),
                    hint: _l10n.addLocation,
                    displayText: showsUnnamedPlaceholder
                        ? _l10n.locationNameUnavailable
                        : data.location,
                    isEmpty: !hasCoordinates && data.location.isEmpty,
                    suffixIcon: !hasCoordinates
                        ? const Icon(TenturaIcons.location)
                        : IconButton(
                            key: const Key(
                              'BeaconCreate.LocationClearButton',
                            ),
                            icon: const Icon(Icons.cancel_rounded),
                            onPressed: () {
                              _locationController.clear();
                              _cubit.setLocation(null, '');
                            },
                          ),
                    onTap: () => unawaited(_pickLocation(context)),
                  );
                },
              ),
        ),
      Padding(
        key: _imagesSectionKey,
        padding: EdgeInsets.symmetric(vertical: tt.rowGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _l10n.beaconImage,
              style: _theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: tt.rowGap),
            const SizedBox(
              height: 360,
              child: ImageTab(),
            ),
          ],
        ),
      ),
    ];
  }

  /// Calendar date at local midnight — Material pickers compare dates only.
  static DateTime _calendarDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Picker row styled like a [TextFormField] but opened via [InkWell], not
  /// `readOnly` + `onTap` on a real text input.
  Widget _pickerField({
    required Key key,
    required String hint,
    required String displayText,
    required Widget? suffixIcon,
    required VoidCallback onTap,
    bool? isEmpty,
  }) {
    final tt = context.tt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        child: InputDecorator(
          key: key,
          decoration: _createFieldDecoration(hintText: hint).copyWith(
            suffixIcon: suffixIcon,
          ),
          isEmpty: isEmpty ?? displayText.isEmpty,
          child: SizedBox(
            width: double.infinity,
            height: tt.buttonHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                displayText,
                style: _theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDeadline(BuildContext context) async {
    final today = _calendarDate(DateTime.now());
    final lastDate = today.add(const Duration(days: 365));
    final rawInitial = _cubit.state.endAt;
    var initialDate = rawInitial != null ? _calendarDate(rawInitial) : today;
    if (initialDate.isBefore(today)) {
      initialDate = today;
    } else if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }

    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      currentDate: today,
      initialDate: initialDate,
      lastDate: lastDate,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    _clearFocusAfterOverlay();
    if (picked != null) {
      _cubit.setDeadline(picked);
    }
  }

  Future<void> _pickEventDates(BuildContext context) async {
    final today = _calendarDate(DateTime.now());
    final lastDate = today.add(const Duration(days: 365));
    final startAt = _cubit.state.startAt;
    final endAt = _cubit.state.endAt;
    DateTimeRange? initialDateRange;
    if (startAt != null) {
      var start = _calendarDate(startAt);
      var end = _calendarDate(endAt ?? startAt);
      if (start.isBefore(today)) {
        start = today;
      }
      if (end.isAfter(lastDate)) {
        end = lastDate;
      }
      if (end.isBefore(start)) {
        end = start;
      }
      initialDateRange = DateTimeRange(start: start, end: end);
    }

    final dateRange = await showDateRangePicker(
      context: context,
      firstDate: today,
      currentDate: today,
      lastDate: lastDate,
      initialDateRange: initialDateRange,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      saveText: _l10n.buttonOk,
    );
    _clearFocusAfterOverlay();
    if (dateRange != null) {
      final sameDay =
          dateRange.start.year == dateRange.end.year &&
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
      final locationName = location.place?.toString() ?? '';

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

  void _onTimingKindChanged(BeaconScheduleKind kind) {
    _timingKindNotifier.value = kind;
    _cubit.setTimingKind(kind);
  }
}

class _DismissRequirementsSheetIntent extends Intent {
  const _DismissRequirementsSheetIntent();
}
