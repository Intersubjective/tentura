import 'package:flutter/material.dart';

abstract final class TestIds {
  static const requestTitle = 'request.title';
  static const requestDescription = 'request.description';
  static const requestPublish = 'request.publish';
  static const requestRecipientsTab = 'request.tab.recipients';

  static const forwardInviteNewPerson = 'forward.invite_new_person';
  static const forwardNote = 'forward.note';
  static const forwardSubmit = 'forward.submit';

  static String forwardRecipient(String userId) => 'forward.recipient.$userId';

  static const inboxOfferHelp = 'inbox.offer_help';
  static const inboxForward = 'inbox.forward';
  static const inboxDismiss = 'inbox.dismiss';
  static String myWorkRoomStatus(String beaconId) =>
      'my_work.room_status.$beaconId';

  static String myWorkCloseNow(String beaconId) =>
      'my_work.close_now.$beaconId';

  /// Stable Updates feed row identity for integration and WebDriver proofs.
  static String updatesReceipt(String receiptId) =>
      'updates-receipt-$receiptId';

  static const helpOfferSearch = 'help_offer.search';
  static const helpOfferMessage = 'help_offer.message';
  static const helpOfferSubmit = 'help_offer.submit';
  static const helpOfferBrowseCategories = 'help_offer.browse_categories';
  static String capabilityChip(String slug) => 'capability.$slug';
  static String capabilitySummaryChip(String slug) =>
      'capability.$slug.summary';

  static const roomMessageInput = 'room.message.input';
  static const roomMessageSend = 'room.message.send';

  /// Press-scale wrapper around a room message bubble (long-press grow).
  static const roomMessageBubblePressScale = 'room.message.bubble_press_scale';
  static String roomMentionSuggestion(String handle) =>
      'room.mention.suggestion.${handle.trim().toLowerCase()}';
  static const beaconForward = 'beacon.forward';
  static const beaconTabThreads = 'beacon.tab.threads';
  static const beaconTabPeople = 'beacon.tab.people';
  static const beaconTabLog = 'beacon.tab.log';

  static const coordinationAskCreate = 'coordination.ask.create';
  static const coordinationPromiseCreate = 'coordination.promise.create';
  static const coordinationBlockerCreate = 'coordination.blocker.create';
  static const coordinationComposerTitle = 'coordination.composer.title';
  static const coordinationComposerSubmit = 'coordination.composer.submit';

  static String coordinationItemMenu(String itemId) =>
      'coordination.item.$itemId.menu';
  static String coordinationItemResolve(String itemId) =>
      'coordination.item.$itemId.resolve';

  static String requestThread(String threadId) => 'request.thread.$threadId';

  static String helpOfferAccept(String userId) => 'help_offer.$userId.accept';
  static String helpOfferDecline(String userId) => 'help_offer.$userId.decline';
  static String helpOfferRemove(String userId) => 'help_offer.$userId.remove';
  static String helpOfferRelease(String userId) => 'help_offer.$userId.release';

  static const admissionReasonInput = 'help_offer.admission_reason.input';
  static const admissionReasonSubmit = 'help_offer.admission_reason.submit';

  static const beaconOverflowMenu = 'beacon.overflow.menu';
  static const beaconOverflowClose = 'beacon.overflow.close';
  static const beaconOverflowRequestStatus = 'beacon.overflow.request_status';
  static const beaconCloseConfirm = 'beacon.close.confirm';

  /// Status bottom-sheet row, keyed by [BeaconStatusMenuRowId.name].
  static String beaconStatusRow(String rowId) => 'beacon.status_row.$rowId';

  /// Author HUD primary action, keyed by [BeaconHudAuthorAction.name]
  /// (e.g. `wrapUpForReview`, `reviewContributions`, `closeNow`).
  static String beaconHudAuthorAction(String action) =>
      'beacon.hud_author_action.$action';

  static const beaconHudMarkEnoughHelpConfirm =
      'beacon.hud.mark_enough_help.confirm';

  static String evaluationParticipant(String userId) =>
      'evaluation.participant.$userId';
  static const evaluationSave = 'evaluation.save';
  static const evaluationSubmit = 'evaluation.submit';

  /// Trust category tile, keyed by [EvaluationTrustSelection.name] of the
  /// option it selects (`zero`, `decreasePending`, `increasePending`).
  static String evaluationTrustOption(String selection) =>
      'evaluation.trust.$selection';
  static const evaluationTrustIntensityLittle =
      'evaluation.trust.intensity.little';
  static const evaluationTrustIntensityLot = 'evaluation.trust.intensity.lot';
  static String evaluationReasonChip(String slug) => 'evaluation.reason.$slug';

  /// Trust graph node tap target, keyed by user id.
  static String graphNode(String userId) => 'graph.node.$userId';

  static const graphExpand = 'graph.expand';
  static const graphOpenDetails = 'graph.open_details';
  static const graphBack = 'graph.back';
  static const graphFit = 'graph.fit';
  static const graphResetToEgo = 'graph.reset_to_ego';
  static const graphCenterView = 'graph.center_view';

  static const graphPersonContextPanel = 'graph.person_context.panel';
  static const graphPersonContextClose = 'graph.person_context.close';
  static const graphPersonContextViewProfile =
      'graph.person_context.view_profile';
  static const graphPersonContextShowMore = 'graph.person_context.show_more';
  static const graphPersonContextTrust = 'graph.person_context.trust';
  static const graphPersonContextSendRequest =
      'graph.person_context.send_request';
  static const graphPersonContextRequestOptions =
      'graph.person_context.request_options';

  static const friendsGraph = 'friends.graph';
  static const friendsCreateInvitation = 'friends.create_invitation';
  static const friendsMore = 'friends.more';

  static ValueKey<String> key(String id) => ValueKey<String>(id);
}
