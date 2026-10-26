import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/constellation_trust_chain.dart';
import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';

/// The chain of trust that brings [personId] onto the viewer's field (#641):
/// "Through Dima → Raf", or a plain statement that no chain the viewer can
/// see reaches them. Nothing for a direct contact.
class ConstellationTrustChainLine extends StatelessWidget {
  const ConstellationTrustChainLine({required this.personId, super.key});

  final String personId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.selectedPersonId != current.selectedPersonId ||
          previous.composition != current.composition ||
          previous.visibility != current.visibility ||
          previous.field != current.field ||
          previous.graphRevision != current.graphRevision,
      builder: (context, state) {
        final cubit = context.read<ConstellationCubit>();
        if (state.selectedPersonId != personId) {
          return const SizedBox.shrink();
        }
        final l10n = L10n.of(context)!;
        final text = switch (cubit.selectedTrustChain) {
          ConstellationTrustChainFound(:final intermediaryIds)
              when intermediaryIds.isNotEmpty =>
            l10n.constellationTrustChainThrough(
              intermediaryIds
                  .map(
                    (id) =>
                        cubit
                            .profileForPersonId(id)
                            ?.displayLabel(
                              l10n.unknownPerson,
                            ) ??
                        cubit.serverTrustChainName(id) ??
                        l10n.unknownPerson,
                  )
                  .join(' → '),
            ),
          ConstellationTrustChainNone() =>
            cubit.hasHiddenLayers
                ? l10n.constellationTrustChainHidden
                : _presenceReason(cubit, l10n) ??
                      l10n.constellationTrustChainNone,
          _ => null,
        };
        if (text == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(top: context.tt.tightGap),
          child: TenturaMetaText(
            text,
            key: const Key('constellation.trust_chain'),
            maxLines: 3,
          ),
        );
      },
    );
  }
}

/// Why the selected person is on the field though no chain of trust reaches them:
/// the Request they forwarded, a Request or Post they share with the viewer,
/// or the viewer's own pin. Null when the field holds nothing of the kind.
String? _presenceReason(ConstellationCubit cubit, L10n l10n) {
  final personId = cubit.state.selectedPersonId;
  if (personId == null) {
    return null;
  }
  final person = cubit.fieldPersonById(personId);
  switch (person?.fieldMembership) {
    case ConstellationFieldMembership.temporary
        when person!.temporaryBeaconId != null:
      final name = person.displayName?.trim() ?? '';
      return name.isEmpty
          ? l10n.constellationTrustChainForwardedUnnamed
          : l10n.constellationTrustChainForwarded(name);
    case ConstellationFieldMembership.bond when person!.bondContexts.isNotEmpty:
      final context = person.bondContexts.first;
      return cubit.isPostId(context.beaconId)
          ? l10n.constellationTrustChainSharedPost(context.title)
          : l10n.constellationTrustChainSharedRequest(context.title);
    case _:
      return cubit.isAnchored(ConstellationAnchorTarget.person(personId))
          ? l10n.constellationTrustChainPinned
          : null;
  }
}
