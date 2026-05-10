import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_view_state.dart';

/// Room surface embedded under beacon detail with a compact beacon header.
class BeaconRoomSurface extends StatelessWidget {
  const BeaconRoomSurface({
    required this.beaconState,
    super.key,
  });

  final BeaconViewState beaconState;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final b = beaconState.beacon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.rowGap / 2,
            tt.screenHPadding,
            tt.rowGap / 4,
          ),
          child: TenturaTechCard(
            padding: tt.cardPadding,
            child: BlocBuilder<RoomCubit, RoomState>(
              buildWhen: (p, c) =>
                  p.roomState?.currentPlan != c.roomState?.currentPlan ||
                  p.roomState?.lastRoomMeaningfulChange !=
                      c.roomState?.lastRoomMeaningfulChange ||
                  p.participants.length != c.participants.length ||
                  p.participants
                          .map((e) => '${e.userId}|${e.nextMoveText}')
                          .join() !=
                      c.participants
                          .map((e) => '${e.userId}|${e.nextMoveText}')
                          .join(),
              builder: (context, rs) {
                final plan = rs.roomState?.currentPlan.trim() ?? '';
                final lm = rs.roomState?.lastRoomMeaningfulChange?.trim() ?? '';
                final nowLine = plan.isNotEmpty
                    ? plan
                    : (lm.isNotEmpty ? lm : '');
                String? youLine;
                for (final p in rs.participants) {
                  if (p.userId == beaconState.myProfile.id) {
                    final nm = (p.nextMoveText ?? '').trim();
                    if (nm.isNotEmpty) youLine = nm;
                    break;
                  }
                }
                final blocker = beaconState.beaconRoomCue?.openBlockerTitle
                    ?.trim();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      b.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    if (nowLine.isNotEmpty) ...[
                      SizedBox(height: tt.rowGap / 4),
                      Text(
                        nowLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (youLine != null) ...[
                      SizedBox(height: tt.rowGap / 4),
                      Text(
                        '${l10n.beaconRoomYouStripTitle}: $youLine',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (blocker != null && blocker.isNotEmpty) ...[
                      SizedBox(height: tt.rowGap / 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.block,
                            size: 16,
                            color: scheme.error,
                          ),
                          SizedBox(width: tt.rowGap / 4),
                          Expanded(
                            child: Text(
                              blocker,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.error),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
        const Expanded(
          child: BeaconRoomBody(hideCoordinationStrips: true),
        ),
      ],
    );
  }
}
