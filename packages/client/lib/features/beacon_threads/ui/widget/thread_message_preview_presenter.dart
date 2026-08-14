import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/coordination_participant_lookup.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

/// Localized last-message preview text for a thread row (never decodes payloads).
String threadMessagePreviewText({
  required ThreadMessagePreview preview,
  required L10n l10n,
  required List<BeaconParticipant> participants,
  required Profile viewerProfile,
}) {
  return switch (preview.kind) {
    ThreadMessagePreviewKind.text => preview.excerpt ?? '',
    ThreadMessagePreviewKind.attachment =>
      (preview.excerpt?.trim().isNotEmpty ?? false)
          ? preview.excerpt!.trim()
          : l10n.beaconRoomAttachmentUntitled,
    ThreadMessagePreviewKind.planUpdated => l10n.beaconRoomSemanticPlan,
    ThreadMessagePreviewKind.factPinned => _factPinnedPreview(preview, l10n),
    ThreadMessagePreviewKind.participantStatus =>
      l10n.beaconRoomSemanticParticipantStatus,
    ThreadMessagePreviewKind.coordination => _coordinationPreview(preview, l10n),
    ThreadMessagePreviewKind.needInfo => l10n.beaconRoomSemanticNeedInfo,
    ThreadMessagePreviewKind.done => l10n.beaconRoomSemanticDone,
    ThreadMessagePreviewKind.poll =>
      preview.pollTitle?.trim().isNotEmpty == true
          ? preview.pollTitle!.trim()
          : l10n.beaconRoomSemanticPoll,
    ThreadMessagePreviewKind.join => _joinPreview(
        preview,
        l10n,
        participants,
        viewerProfile,
      ),
    int() => throw StateError('Unknown preview kind: ${preview.kind}'),
  };
}

String _factPinnedPreview(ThreadMessagePreview preview, L10n l10n) {
  final title = preview.factTitle?.trim();
  if (title != null && title.isNotEmpty) return title;
  return switch (preview.factVisibility) {
    1 => l10n.beaconRoomSemanticPublicFact,
    2 => l10n.beaconRoomSemanticRoomFact,
    _ => l10n.beaconRoomSemanticPublicFact,
  };
}

String _coordinationPreview(ThreadMessagePreview preview, L10n l10n) {
  final itemKind = preview.itemKind == null
      ? null
      : CoordinationItemKind.fromInt(preview.itemKind!);
  final eventKind = preview.linkedEventKind == null
      ? null
      : CoordinationItemEventKind.fromInt(preview.linkedEventKind!);
  if (itemKind != null && eventKind != null) {
    final label = coordinationEventTimelineLabel(
      l10n,
      itemKind,
      eventKind,
    );
    final title = preview.itemTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return '$label: $title';
    }
    return label;
  }
  final title = preview.itemTitle?.trim();
  if (title != null && title.isNotEmpty) return title;
  return l10n.beaconRoomSemanticBlocker;
}

String _joinPreview(
  ThreadMessagePreview preview,
  L10n l10n,
  List<BeaconParticipant> participants,
  Profile viewerProfile,
) {
  final joinedId = preview.joinedUserId?.trim();
  if (joinedId == null || joinedId.isEmpty) {
    return l10n.beaconRoomSemanticParticipantJoined;
  }
  final joinedName = _participantName(
    participants,
    joinedId,
    viewerProfile,
    l10n,
  );
  if (joinedName == null) {
    return l10n.beaconRoomSemanticParticipantJoined;
  }
  final reason = preview.admissionReason?.trim() ?? '';
  if (reason == 'autoAdmit') {
    return l10n.beaconRoomParticipantJoinedAutoAdmit(joinedName);
  }
  return l10n.beaconRoomSemanticParticipantJoined;
}

String? threadMessageAuthorPrefix({
  required String? authorId,
  required L10n l10n,
  required List<BeaconParticipant> participants,
  required Profile viewerProfile,
}) {
  final id = authorId?.trim();
  if (id == null || id.isEmpty) return null;
  if (id == viewerProfile.id) {
    return '${l10n.labelYou}: ';
  }
  final name = _participantName(participants, id, viewerProfile, l10n);
  if (name == null) return null;
  return '$name: ';
}

String? _participantName(
  List<BeaconParticipant> participants,
  String userId,
  Profile viewerProfile,
  L10n l10n,
) {
  final row = participants.where((p) => p.userId == userId).firstOrNull;
  if (row != null && row.userTitle.trim().isNotEmpty) {
    return SelfUserHighlight.displayName(
      l10n,
      profileForBeaconParticipant(row, viewerProfile: viewerProfile),
      viewerProfile.id,
    );
  }
  if (userId == viewerProfile.id) {
    return l10n.labelYou;
  }
  final label = participantDisplayLabel(
    participants,
    userId,
    l10n.unknownPerson,
    viewerProfile: viewerProfile,
  );
  if (label == l10n.unknownPerson) return null;
  return label;
}

RequestThreadKind threadKindForItem(CoordinationItem item) => switch (item.kind) {
  CoordinationItemKind.ask => RequestThreadKind.ask,
  CoordinationItemKind.promise => RequestThreadKind.promise,
  CoordinationItemKind.blocker => RequestThreadKind.blocker,
  CoordinationItemKind.plan => RequestThreadKind.ask,
};
