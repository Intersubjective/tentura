import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/activity_list.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> showBeaconActivitySheet(
  BuildContext pageContext, {
  required BeaconViewCubit cubit,
  required void Function(BeaconActivityEvent event) onTapCoordinationEvent,
}) async {
  await showTenturaAdaptiveSheet<void>(
    context: pageContext,
    builder: (ctx) => _BeaconActivitySheetBody(
      cubit: cubit,
      onTapCoordinationEvent: onTapCoordinationEvent,
    ),
  );
}

class _BeaconActivitySheetBody extends StatelessWidget {
  const _BeaconActivitySheetBody({
    required this.cubit,
    required this.onTapCoordinationEvent,
  });

  final BeaconViewCubit cubit;
  final void Function(BeaconActivityEvent event) onTapCoordinationEvent;

  void _onRowTap(BuildContext context, BeaconActivityEvent event) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onTapCoordinationEvent(event);
    });
  }

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
          child: BlocBuilder<BeaconViewCubit, BeaconViewState>(
            bloc: cubit,
            buildWhen: (previous, current) =>
                previous.roomActivityEvents != current.roomActivityEvents ||
                previous.roomParticipants != current.roomParticipants ||
                previous.beacon != current.beacon ||
                previous.isBeaconMine != current.isBeaconMine,
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.labelBeaconTabLog,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SizedBox(height: tt.rowGap),
                  Expanded(
                    child: SingleChildScrollView(
                      child: BeaconActivityList(
                        timeline: const [],
                        beacon: state.beacon,
                        isAuthorView: state.isBeaconMine,
                        roomActivityEvents: state.roomActivityEvents,
                        coordinationLogOnly: true,
                        onTapCoordinationEvent: (event) =>
                            _onRowTap(context, event),
                        actors: {
                          for (final participant in state.roomParticipants)
                            participant.userId: participant,
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
