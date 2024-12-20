import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/widget/deep_back_button.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_author_info.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_mine_control.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_tile_control.dart';
import 'package:tentura/features/comment/ui/widget/comment_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/beacon_view_cubit.dart';
import '../widget/new_comment_input.dart';

@RoutePage()
class BeaconViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconViewScreen({
    @queryParam this.id = '',
    super.key,
  });

  final String id;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (context) => BeaconViewCubit(
          myProfile: GetIt.I<ProfileCubit>().state.profile,
          id: id,
        ),
        child: this,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beacon'),
        leading: const DeepBackButton(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: BlocSelector<BeaconViewCubit, BeaconViewState, FetchStatus>(
            selector: (state) => state.status,
            builder: (context, status) => status.isLoading
                ? const LinearPiActive()
                : const SizedBox(height: 4),
          ),
        ),
      ),
      bottomSheet: const NewCommentInput(),
      body: BlocConsumer<BeaconViewCubit, BeaconViewState>(
        listener: showSnackBarError,
        listenWhen: (p, c) => c.hasError,
        buildWhen: (p, c) => c.status.isSuccess,
        builder: (context, state) {
          final beacon = state.beacon;
          return ListView(
            padding: kPaddingH + const EdgeInsets.only(bottom: 80),
            children: [
              // User row (Avatar and Name)
              BeaconAuthorInfo(
                author: beacon.author,
                key: ValueKey(beacon.author),
              ),

              // Beacon Info
              BeaconInfo(
                key: ValueKey(beacon),
                beacon: beacon,
                isTitleLarge: true,
                isShowMoreEnabled: false,
              ),

              // Buttons Row
              Padding(
                padding: kPaddingSmallV,
                child: state.isBeaconMine
                    ? BeaconMineControl(
                        beacon: beacon,
                        key: ValueKey(beacon.id),
                      )
                    : BeaconTileControl(
                        beacon: beacon,
                        key: ValueKey(beacon.id),
                      ),
              ),

              // Comments Section
              const Text(
                'Comments',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              // Comments list
              for (final comment in state.comments.reversed)
                CommentCard(
                  comment: comment,
                  key: ValueKey(comment),
                  isMine: state.checkIfCommentIsMine(comment),
                ),

              // Show All Button
              if (state.comments.isNotEmpty && state.hasNotReachedMax)
                Padding(
                  padding: kPaddingSmallV,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: context.read<BeaconViewCubit>().showAll,
                      child: const Text('Show all comments'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
