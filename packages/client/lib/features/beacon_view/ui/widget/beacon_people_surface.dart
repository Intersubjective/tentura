import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_people_tab_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// PEOPLE surface: unchanged [BeaconPeopleTabBody] with today's padding.
class BeaconPeopleSurface extends StatefulWidget {
  const BeaconPeopleSurface({
    required this.beaconViewCubit,
    required this.beaconState,
    required this.focusUserId,
    required this.peopleTabAttentionActive,
    this.peopleFoldEpoch = 0,
    super.key,
  });

  final BeaconViewCubit beaconViewCubit;
  final BeaconViewState beaconState;
  final String? focusUserId;
  final bool peopleTabAttentionActive;

  /// Bumped on same-tab reselect to remount People folds to defaults.
  final int peopleFoldEpoch;

  @override
  State<BeaconPeopleSurface> createState() => _BeaconPeopleSurfaceState();
}

class _BeaconPeopleSurfaceState extends State<BeaconPeopleSurface> {
  String? _markedBeaconId;

  @override
  void initState() {
    super.initState();
    _markIfEligible();
  }

  @override
  void didUpdateWidget(BeaconPeopleSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _markIfEligible();
  }

  void _markIfEligible() {
    final state = widget.beaconState;
    if (!state.beaconContextLoaded || !state.isAuthorOrSteward) return;
    if (_markedBeaconId == state.beacon.id) return;
    _markedBeaconId = state.beacon.id;
    unawaited(widget.beaconViewCubit.markPeopleSeen());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(
          key: ValueKey('people-${widget.peopleFoldEpoch}'),
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.cardPadding.top,
            tt.screenHPadding,
            tt.cardPadding.bottom,
          ),
          sliver: SliverToBoxAdapter(
            child: BeaconPeopleTabBody(
              state: widget.beaconState,
              beaconViewCubit: widget.beaconViewCubit,
              l10n: l10n,
              focusUserId: widget.focusUserId,
              peopleTabAttentionActive: widget.peopleTabAttentionActive,
            ),
          ),
        ),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: SizedBox.shrink(),
        ),
      ],
    );
  }
}
