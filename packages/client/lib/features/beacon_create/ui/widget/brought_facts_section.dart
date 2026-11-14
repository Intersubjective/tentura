import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_create_cubit.dart';

/// «Facts you're bringing (N)» on the create screen: the facts carried into
/// the draft, each with a ✕. There is no way to add a fact here; nothing is
/// shown while there are none.
class BroughtFactsSection extends StatelessWidget {
  const BroughtFactsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BeaconCreateCubit>();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return BlocBuilder<BeaconCreateCubit, BeaconCreateState>(
      bloc: cubit,
      buildWhen: (p, c) =>
          p.broughtFacts != c.broughtFacts ||
          p.factsNotBrought != c.factsNotBrought,
      builder: (context, state) {
        final facts = state.broughtFacts;
        if (facts.isEmpty && state.factsNotBrought == 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(bottom: tt.rowGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (facts.isNotEmpty) ...[
                Text(
                  l10n.beaconCreateBroughtFactsTitle(facts.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final fact in facts)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fact.factText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.beaconCreateBroughtFactsRemove,
                        onPressed: () =>
                            unawaited(cubit.removeBroughtFact(fact.id)),
                      ),
                    ],
                  ),
              ],
              if (state.factsNotBrought > 0)
                Text(
                  l10n.beaconCreateFactsNotBrought(state.factsNotBrought),
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
            ],
          ),
        );
      },
    );
  }
}
