import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_fact_actions.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const double _kFactsGridMinWidth = 520;
const double _kFactsGridExtent = 280;

Future<void> showBeaconPinnedFactsSheet(
  BuildContext pageContext, {
  required BeaconViewCubit cubit,
}) async {
  final seenAtOpen = cubit.state.pinnedFactsSeenAt;
  try {
    await showTenturaAdaptiveSheet<void>(
      context: pageContext,
      builder: (ctx) => _BeaconPinnedFactsSheetBody(
        cubit: cubit,
        pageContext: pageContext,
        newSince: seenAtOpen,
      ),
    );
  } finally {
    cubit.markPinnedFactsSeen();
  }
}

class _BeaconPinnedFactsSheetBody extends StatelessWidget {
  const _BeaconPinnedFactsSheetBody({
    required this.cubit,
    required this.pageContext,
    required this.newSince,
  });

  final BeaconViewCubit cubit;
  final BuildContext pageContext;
  final DateTime? newSince;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final maxH = MediaQuery.sizeOf(context).height * 0.9;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.tightGap * 2,
            tt.screenHPadding,
            tt.rowGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.beaconFactsSheetTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: tt.rowGap),
              Expanded(
                child: BlocBuilder<BeaconViewCubit, BeaconViewState>(
                  bloc: cubit,
                  buildWhen: (p, c) => p.factCards != c.factCards,
                  builder: (context, state) {
                    final facts = activePinnedFacts(state.factCards);
                    if (facts.isEmpty) {
                      return Text(
                        l10n.beaconFactsSheetEmpty,
                        style: TenturaText.bodyMedium(tt.textMuted),
                      );
                    }
                    final viewerId = state.myProfile.id;
                    Widget cardFor(BeaconFactCard fact) => BeaconPinnedFactCard(
                      fact: fact,
                      l10n: l10n,
                      isNew: pinnedFactIsNew(
                        fact: fact,
                        seenAt: newSince,
                        viewerUserId: viewerId,
                      ),
                      onManage: () => unawaited(
                        showBeaconFactActions(
                          pageContext,
                          cubit: cubit,
                          fact: fact,
                        ),
                      ),
                    );

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < _kFactsGridMinWidth) {
                          return ListView.separated(
                            itemCount: facts.length,
                            separatorBuilder: (_, _) =>
                                SizedBox(height: tt.rowGap),
                            itemBuilder: (_, index) => cardFor(facts[index]),
                          );
                        }
                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: _kFactsGridExtent,
                                mainAxisSpacing: tt.rowGap,
                                crossAxisSpacing: tt.rowGap,
                                childAspectRatio: 0.72,
                              ),
                          itemCount: facts.length,
                          itemBuilder: (_, index) => cardFor(facts[index]),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
