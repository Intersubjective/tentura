import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_author_invites_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_author_invites_section.dart';
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
    this.postBuddingEnabled = kPostBuddingEnabled,
    this.authorInvitesCubit,
    super.key,
  });

  final BeaconViewCubit beaconViewCubit;
  final BeaconViewState beaconState;
  final String? focusUserId;
  final bool peopleTabAttentionActive;

  /// Bumped on same-tab reselect to remount People folds to defaults.
  final int peopleFoldEpoch;

  /// [kPostBuddingEnabled], injectable for tests.
  final bool postBuddingEnabled;

  /// Test override for the author's invites section cubit (plan D4).
  final BeaconAuthorInvitesCubit? authorInvitesCubit;

  @override
  State<BeaconPeopleSurface> createState() => _BeaconPeopleSurfaceState();
}

class _BeaconPeopleSurfaceState extends State<BeaconPeopleSurface> {
  BeaconAuthorInvitesCubit? _invitesCubit;

  bool get _showsAuthorInvites {
    final state = widget.beaconState;
    return widget.postBuddingEnabled &&
        state.myProfile.id.isNotEmpty &&
        state.beacon.author.id == state.myProfile.id;
  }

  /// The author's invites section loads lazily, once the viewer is known to
  /// be the Request author; nobody else ever calls its queries.
  BeaconAuthorInvitesCubit? get _authorInvites {
    if (!_showsAuthorInvites) return null;
    if (_invitesCubit case final cubit?) return cubit;
    final cubit =
        widget.authorInvitesCubit ??
        BeaconAuthorInvitesCubit(beaconId: widget.beaconState.beacon.id);
    unawaited(cubit.load());
    return _invitesCubit = cubit;
  }

  @override
  void dispose() {
    if (widget.authorInvitesCubit == null) unawaited(_invitesCubit?.close());
    super.dispose();
  }

  // Mount equals visible: BeaconViewScreen._buildSelectedSurface mounts only
  // the active tab's surface, so initState runs when People becomes visible.
  // The cubit itself gates on author/steward and unseen offers.
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(BeaconPeopleSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.beaconState;
    final state = widget.beaconState;
    if (old.helpOffers != state.helpOffers ||
        (!old.isAuthorOrSteward && state.isAuthorOrSteward)) {
      _report();
    }
  }

  void _report() =>
      unawaited(widget.beaconViewCubit.reportPeopleSurfaceViewed());

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_authorInvites case final invites?)
                  BlocProvider.value(
                    value: invites,
                    child: BeaconAuthorInvitesSection(
                      excludedUserIds: {
                        for (final p in widget.beaconState.admittedHelperRoster)
                          p.id,
                      },
                    ),
                  ),
                BeaconPeopleTabBody(
                  state: widget.beaconState,
                  beaconViewCubit: widget.beaconViewCubit,
                  l10n: l10n,
                  focusUserId: widget.focusUserId,
                  peopleTabAttentionActive: widget.peopleTabAttentionActive,
                ),
              ],
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
