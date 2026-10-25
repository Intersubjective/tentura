import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Lets the viewer tick people on the Field for tag [tagId]. Nothing is sent
/// while the sheet is open; closing it (barrier, back, drag) sends the whole
/// change as one batch. Throws when the batch cannot be applied.
Future<void> showAddPeopleSheet(
  BuildContext context, {
  required String tagId,
}) async {
  final peopleTags = GetIt.I<PeopleTagsCase>();
  final people =
      GetIt.I<ConstellationFieldStoreCase>().current.field?.peers ??
      const <ConstellationPerson>[];
  final initial = peopleTags.peopleInTag(tagId);
  final checked = {...initial};
  await showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (_) => _AddPeopleSheet(people: people, checked: checked),
  );
  final ops = [
    for (final id in checked.difference(initial))
      PersonTagMemberOp(tagId: tagId, personId: id, add: true),
    for (final id in initial.difference(checked))
      PersonTagMemberOp(tagId: tagId, personId: id, add: false),
  ];
  if (ops.isEmpty) return;
  await peopleTags.applyMembership(ops);
}

class _AddPeopleSheet extends StatefulWidget {
  const _AddPeopleSheet({required this.people, required this.checked});

  final List<ConstellationPerson> people;

  /// Ids of the ticked people; edited in place so the opener sees the result.
  final Set<String> checked;

  @override
  State<_AddPeopleSheet> createState() => _AddPeopleSheetState();
}

class _AddPeopleSheetState extends State<_AddPeopleSheet> {
  String _query = '';

  bool _matches(ConstellationPerson p) =>
      _query.isEmpty ||
      (p.displayName ?? '').toLowerCase().contains(_query) ||
      (p.handle ?? '').toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
          child: TextField(
            key: const Key('add-people-search'),
            style: tenturaFormFieldTextStyle(context),
            decoration: tenturaFormFieldDecoration(
              context,
              labelText: l10n.peopleTagsSearchPeople,
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in widget.people.where(_matches))
                CheckboxListTile(
                  value: widget.checked.contains(p.id),
                  onChanged: (on) => setState(() {
                    if (on ?? false) {
                      widget.checked.add(p.id);
                    } else {
                      widget.checked.remove(p.id);
                    }
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(p.displayName ?? p.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
