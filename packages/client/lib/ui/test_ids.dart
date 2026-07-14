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
  static const helpOfferSearch = 'help_offer.search';
  static const helpOfferMessage = 'help_offer.message';
  static const helpOfferSubmit = 'help_offer.submit';
  static String capabilityChip(String slug) => 'capability.$slug';

  static const roomMessageInput = 'room.message.input';
  static const roomMessageSend = 'room.message.send';
  static const beaconRoomOpen = 'beacon.room.open';
  static const beaconTabItems = 'beacon.tab.items';
  static const beaconTabPeople = 'beacon.tab.people';
  static const beaconTabLog = 'beacon.tab.log';

  static const coordinationAskCreate = 'coordination.ask.create';
  static const coordinationPromiseCreate = 'coordination.promise.create';
  static const coordinationBlockerCreate = 'coordination.blocker.create';
  static const coordinationComposerTitle = 'coordination.composer.title';
  static const coordinationComposerBody = 'coordination.composer.body';
  static const coordinationComposerSubmit = 'coordination.composer.submit';

  static String coordinationItemMenu(String itemId) =>
      'coordination.item.$itemId.menu';
  static String coordinationItemResolve(String itemId) =>
      'coordination.item.$itemId.resolve';

  static String helpOfferAccept(String userId) => 'help_offer.$userId.accept';
  static String helpOfferDecline(String userId) => 'help_offer.$userId.decline';
  static String helpOfferRemove(String userId) => 'help_offer.$userId.remove';

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

  static ValueKey<String> key(String id) => ValueKey<String>(id);
}
