import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';

/// Why a bond or temporary person is on the viewer's field: the Request the
/// two work on together, or the Request that makes them visible for now.
/// Nothing for anyone else.
class ConstellationPresenceLine extends StatelessWidget {
  const ConstellationPresenceLine({required this.personId, super.key});

  final String personId;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ConstellationCubit>();
    final person = cubit.fieldPersonById(personId);
    final l10n = L10n.of(context)!;
    final text = switch (person?.fieldMembership) {
      ConstellationFieldMembership.bond when person!.bondContexts.isNotEmpty =>
        l10n.peopleTagsWorkingTogether(person.bondContexts.first.title),
      ConstellationFieldMembership.temporary
          when person!.temporaryBeaconId != null =>
        switch (cubit.requestById(person.temporaryBeaconId!)) {
          final request? => l10n.peopleTagsTemporary(request.title),
          null => null,
        },
      _ => null,
    };
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: context.tt.tightGap),
      child: TenturaMetaText(text, maxLines: 3),
    );
  }
}
