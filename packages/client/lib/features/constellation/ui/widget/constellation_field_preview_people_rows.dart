import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/post_view/ui/util/post_participants_sheet_request.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_field_preview_people.dart';
import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';

const _kFieldPreviewAvatarMax = 3;

/// Participants and forward-chain avatar rows on Request/Post preview sheets.
class ConstellationFieldPreviewPeopleRows extends StatelessWidget {
  const ConstellationFieldPreviewPeopleRows({
    required this.beaconId,
    required this.isPost,
    this.hiddenReachCount = 0,
    this.onOpenParticipants,
    this.onOpenForwardedThrough,
    super.key,
  });

  final String beaconId;
  final bool isPost;
  final int hiddenReachCount;
  final VoidCallback? onOpenParticipants;
  final VoidCallback? onOpenForwardedThrough;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.selectedRequestId != current.selectedRequestId ||
          previous.graphRevision != current.graphRevision ||
          previous.field != current.field,
      builder: (context, _) {
        final cubit = context.read<ConstellationCubit>();
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final webs = cubit.memberWebsForBeacon(beaconId);
        bool peerOnField(String id) => cubit.fieldPersonById(id) != null;
        final participants = constellationFieldPreviewMemberStack(
          webs: webs,
          state: ConstellationMemberWebState.inside,
          viewerId: cubit.viewerId,
          peerOnField: peerOnField,
          profileFor: cubit.profileForPersonId,
        );
        final forwarded = constellationFieldPreviewMemberStack(
          webs: webs,
          state: ConstellationMemberWebState.forwarded,
          viewerId: cubit.viewerId,
          peerOnField: peerOnField,
          profileFor: cubit.profileForPersonId,
          additionalHiddenCount: isPost ? hiddenReachCount : 0,
        );
        final rows = <Widget>[];
        if (!participants.isEmpty) {
          rows.add(
            ConstellationFieldPreviewAvatarRow(
              key: const Key('constellation.field_preview.participants'),
              title: l10n.constellationPreviewParticipantsTitle,
              stack: participants,
              onTap: onOpenParticipants,
            ),
          );
        }
        if (!forwarded.isEmpty) {
          if (rows.isNotEmpty) {
            rows.add(SizedBox(height: tt.rowGap));
          }
          rows.add(
            ConstellationFieldPreviewAvatarRow(
              key: const Key('constellation.field_preview.forwarded'),
              title: l10n.constellationPreviewForwardedThroughTitle,
              stack: forwarded,
              onTap: onOpenForwardedThrough,
            ),
          );
        }
        if (rows.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

void constellationFieldPreviewOpenPostParticipants(
  VoidCallback openPost,
  String postId,
) {
  PostParticipantsSheetRequest.instance.pending = postId;
  openPost();
}

/// One labeled [TenturaAvatarStack] row (pattern from beacon showcase team strip).
class ConstellationFieldPreviewAvatarRow extends StatelessWidget {
  const ConstellationFieldPreviewAvatarRow({
    required this.title,
    required this.stack,
    this.onTap,
    super.key,
  });

  final String title;
  final ConstellationFieldPreviewMemberStack stack;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!constellationFieldPreviewStackHasDrawableContent(stack)) {
      return const SizedBox.shrink();
    }
    final tt = context.tt;
    final faces = stack.profiles;
    final extra = constellationFieldPreviewStackPlusCount(stack);
    final avatarRow = Row(
      children: [
        if (faces.isNotEmpty)
          TenturaAvatarStack(
            profiles: faces,
            max: _kFieldPreviewAvatarMax,
          ),
        if (extra > 0) ...[
          if (faces.isNotEmpty) SizedBox(width: tt.tightGap),
          Text(
            '+$extra',
            style: TenturaText.status(tt.textMuted),
          ),
        ],
      ],
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TenturaTypeLabel(title),
        SizedBox(height: tt.tightGap),
        avatarRow,
      ],
    );
    if (onTap == null) {
      return content;
    }
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tt.buttonRadius),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: tt.tightGap),
          child: content,
        ),
      ),
    );
  }
}
