import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_people_labels.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';

/// Compact read-only peek at a chat message author's help-offer commitment.
///
/// Uses participant fields already on the room tile — no fetch.
Future<void> showAuthorCommitmentSheet(
  BuildContext context, {
  required Profile author,
  required BeaconParticipant participant,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: false,
    isScrollControlled: true,
    maxWidth: 360,
    maxHeightFraction: 0.5,
    builder: (sheetContext) {
      return _AuthorCommitmentSheetBody(
        author: author,
        participant: participant,
      );
    },
  );
}

class _AuthorCommitmentSheetBody extends StatelessWidget {
  const _AuthorCommitmentSheetBody({
    required this.author,
    required this.participant,
  });

  final Profile author;
  final BeaconParticipant participant;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final scheme = theme.colorScheme;
    final tags = helpOfferTypeSlugs(participant.helpType)
        .take(4)
        .map(CapabilityTag.fromSlug)
        .whereType<CapabilityTag>()
        .toList();
    final offerNote = participant.offerNote.trim();
    final nextMove = participant.nextMoveText?.trim() ?? '';
    final statusLine =
        '${beaconPeopleRoleLabel(l10n, participant.role)} · '
        '${beaconPeopleStatusLabel(l10n, participant.status, null)}';
    final name = author.displayLabel(l10n.unknownPerson);
    final roleLabel = participant.roleLabel;
    final roleDisplay = roleLabel == null
        ? null
        : (roleLabel.trim().isEmpty
              ? l10n.helpOfferRoleLabelPlaceholder
              : roleLabel.trim());

    return SafeArea(
      child: Semantics(
        label: l10n.roomAuthorCommitmentSheetTitle,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tt.cardPadding.left,
            tt.rowGap,
            tt.cardPadding.right,
            tt.sectionGap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              SizedBox(height: tt.tightGap),
              Text(
                statusLine,
                style: TenturaText.status(scheme.onSurfaceVariant),
              ),
              if (roleDisplay != null) ...[
                SizedBox(height: tt.rowGap),
                Text(
                  l10n.helpOfferRoleLabelField,
                  style: TenturaText.status(scheme.onSurfaceVariant),
                ),
                SizedBox(height: tt.tightGap),
                Text(
                  roleDisplay,
                  style: TenturaText.body(scheme.onSurface),
                ),
              ],
              if (tags.isNotEmpty) ...[
                SizedBox(height: tt.rowGap),
                for (final tag in tags) ...[
                  Row(
                    children: [
                      TenturaCapabilityGlyph(
                        tag: tag,
                        size: tt.avatarTinySize,
                      ),
                      SizedBox(width: tt.iconTextGap),
                      Expanded(
                        child: Text(
                          tag.labelOf(l10n),
                          style: TenturaText.body(scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: tt.tightGap),
                ],
              ],
              if (offerNote.isNotEmpty) ...[
                SizedBox(height: tt.rowGap),
                ShowMoreText(
                  offerNote,
                  style: TenturaText.body(scheme.onSurface),
                  colorClickableText: scheme.primary,
                  annotations: buildUrlAnnotations(linkColor: tt.info),
                ),
              ],
              if (nextMove.isNotEmpty) ...[
                SizedBox(height: tt.rowGap),
                Text(
                  nextMove,
                  style: TenturaText.bodySmall(scheme.onSurface),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
