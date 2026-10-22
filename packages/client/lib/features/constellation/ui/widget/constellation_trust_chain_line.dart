import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_trust_chain.dart';
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
          previous.field != current.field,
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
                        l10n.unknownPerson,
                  )
                  .join(' → '),
            ),
          ConstellationTrustChainNone() =>
            cubit.hasHiddenLayers
                ? l10n.constellationTrustChainHidden
                : l10n.constellationTrustChainNone,
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
