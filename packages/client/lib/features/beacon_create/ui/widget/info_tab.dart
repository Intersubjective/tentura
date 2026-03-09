import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import 'package:tentura/features/context/ui/widget/context_drop_down.dart';
import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';

import '../bloc/beacon_create_cubit.dart';
import '../dialog/add_tag_dialog.dart';

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

  @override
  void dispose() {
    _dateRangeController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
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

      // Context
      const Padding(
        padding: kPaddingSmallV,
        child: ContextDropDown(),
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
                  location.place?.toString() ?? location.coords.toString();

              _locationController.text = locationName;
              _cubit.setLocation(location.coords, locationName);
            }
          },
        ),
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

      // Tags
      Padding(
        padding: kPaddingSmallV,
        child: Text(_l10n.tagsText),
      ),
      BlocSelector<BeaconCreateCubit, BeaconCreateState, Set<String>>(
        selector: (state) => state.tags,
        builder: (_, tags) => Wrap(
          runSpacing: kSpacingSmall,
          spacing: kSpacingSmall,
          children: [
            // Add Tag
            ActionChip(
              label: Text(
                _l10n.addTagText,
                style: _theme.chipTheme.labelStyle,
              ),
              onPressed: tags.length < 5
                  ? () async {
                      final tag = await BeaconAddTagDialog.show(context);
                      if (tag != null) {
                        _cubit.addTag(tag);
                      }
                    }
                  : null,
            ),

            // Added Tags
            for (final tag in tags)
              Chip(
                label: Text(tag),
                deleteIconColor: _theme.colorScheme.onPrimary,
                onDeleted: () => _cubit.removeTag(tag),
              ),
          ],
        ),
      ),
    ],
  );

  String _formatDateRange(DateTime? start, DateTime? end) =>
      start == null || end == null
      ? ''
      : '${dateFormatYMD(start)} - ${dateFormatYMD(end)}';
}
