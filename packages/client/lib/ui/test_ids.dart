import 'package:flutter/material.dart';

abstract final class TestIds {
  static const requestTitle = 'request.title';
  static const requestDescription = 'request.description';
  static const requestPublish = 'request.publish';
  static const requestMakeLive = 'request.make_live';
  static const requestRecipientsTab = 'request.tab.recipients';
  static const requestDiscoverableToggle = 'request.discoverable_toggle';

  static const forwardInviteNewPerson = 'forward.invite_new_person';
  static const forwardClearSelection = 'forward.clear_selection';
  static const forwardNote = 'forward.note';
  static const forwardSubmit = 'forward.submit';

  static String forwardRecipient(String userId) => 'forward.recipient.$userId';

  static String forwardRecipientCheckbox(String userId) =>
      'forward.recipient.checkbox.$userId';

  static String activityPromptPin(String receiptId) =>
      'activity-prompt-pin-$receiptId';

  static const activityPromptCollapsed = 'activity-prompt-collapsed';

  static const activityForYouHeader = 'activity-for-you-header';

  static const activityNewItemsPill = 'activity-new-items-pill';

  static String activityOffer(String beaconId) => 'activity-offer-$beaconId';

  static String activityForwardRow(String beaconId) =>
      'activity-forward-row-$beaconId';

  static const activityWatchingDigest = 'activity-watching-digest';

  /// Manifest §0.4 — the Settings **Reset counters** command (D15).
  static const attentionResetCounters = 'attention.reset_counters';

  static const inboxOfferHelp = 'inbox.offer_help';
  static const inboxForward = 'inbox.forward';
  static const inboxDismiss = 'inbox.dismiss';
  static String myWorkRoomStatus(String beaconId) =>
      'my_work.room_status.$beaconId';

  static String myWorkCloseNow(String beaconId) =>
      'my_work.close_now.$beaconId';

  static String myWorkObligation(String receiptId) =>
      'my_work.obligation.$receiptId';

  static String myWorkWhatsNew(String beaconId) =>
      'my_work.whats_new.$beaconId';

  /// U087 — the card's latest-message line.
  static String myWorkLatestMessage(String beaconId) =>
      'my_work.latest_message.$beaconId';

  /// Stable Updates feed row identity for integration and WebDriver proofs.
  static String updatesReceipt(String receiptId) =>
      'updates-receipt-$receiptId';

  /// Passive read-state signal, separate from the receipt's stable identity.
  static String updatesReceiptReadState(
    String receiptId, {
    required bool seen,
  }) => 'updates-read-state-$receiptId-${seen ? 'seen' : 'unseen'}';

  static const inviteAcceptedSetupOpen = 'invite_accepted.setup.open';
  static const inviteAcceptedSetupRetry = 'invite_accepted.setup.retry';
  static const inviteAcceptedSetupModal = 'invite_accepted.setup.modal';
  static const inviteAcceptedSetupClose = 'invite_accepted.setup.close';
  static const inviteAcceptedSetupDragHandle =
      'invite_accepted.setup.drag_handle';
  static const inviteAcceptedSetupChangePrivateName =
      'invite_accepted.setup.change_private_name';
  static const inviteAcceptedSetupPrivateName =
      'invite_accepted.setup.private_name';
  static const inviteAcceptedSetupSave = 'invite_accepted.setup.save';
  static const inviteAcceptedSetupSkip = 'invite_accepted.setup.skip';
  static const inviteAcceptedSetupError = 'invite_accepted.setup.error';

  static const helpOfferSearch = 'help_offer.search';
  static const helpOfferMessage = 'help_offer.message';
  static const helpOfferSubmit = 'help_offer.submit';
  static const helpOfferBrowseCategories = 'help_offer.browse_categories';
  static String capabilityChip(String slug) => 'capability.$slug';
  static String capabilitySummaryChip(String slug) =>
      'capability.$slug.summary';

  static const roomMessageInput = 'room.message.input';
  static const roomMessagePaste = 'room.message.paste';
  static const roomMessageSend = 'room.message.send';

  /// Press-scale wrapper around a room message bubble (long-press grow).
  static const roomMessageBubblePressScale = 'room.message.bubble_press_scale';

  /// Desktop hover-toolbar heart that opens the reaction picker.
  static const roomMessageReactionPickerButton =
      'room.message.reaction_picker_button';
  static const roomAuthorCommitmentGlyphs =
      'room.message.author_commitment_glyphs';

  /// Close (✕) of the Rating search. The Rating screen keeps the browser
  /// focus on its search field when this button is pressed
  /// (`keepTextInputFocusOnPress`), so renaming it changes runtime
  /// behaviour, not only tests (#603).
  static const ratingSearchClear = 'rating.search.clear';

  /// Identifier prefix of every mention suggestion row. The web composer
  /// keeps the browser focus on its field when one of these rows is pressed
  /// (`keepTextInputFocusOnPress` in `BasicChatBody`), so the fix for #688
  /// depends on this value: renaming it changes runtime behaviour, not only
  /// tests.
  static const roomMentionSuggestionPrefix = 'room.mention.suggestion.';
  static String roomMentionSuggestion(String handle) =>
      '$roomMentionSuggestionPrefix${handle.trim().toLowerCase()}';
  static const roomEmojiButton = 'room.emoji.button';
  static const roomEmojiPicker = 'room.emoji.picker';

  /// Identifier prefix of every emoji suggestion row. Like
  /// [roomMentionSuggestionPrefix], the fix for #688 depends on it.
  static const roomEmojiSuggestionPrefix = 'room.emoji.suggestion.';
  static String roomEmojiSuggestion(String shortcode) =>
      '$roomEmojiSuggestionPrefix$shortcode';
  static const beaconForward = 'beacon.forward';
  static const beaconTabNow = 'beacon.tab.now';
  static const beaconTabPlan = 'beacon.tab.plan';
  static const planStepTitle = 'plan.step.title';
  static const planStepDescription = 'plan.step.description';
  static const beaconTabRoom = 'beacon.tab.room';
  static const childRequestCreate = 'request.child.create';
  static const childRequestsActive = 'request.children.active';
  static const childRequestsFinished = 'request.children.finished';
  static const childRequestParentLink = 'request.child.parent';
  static String childRequestCard(String beaconId) => 'request.child.$beaconId';
  static const beaconTabPeople = 'beacon.tab.people';
  static const beaconDetailsOpen = 'beacon.details.open';
  static const beaconFactsOpen = 'beacon.facts.open';
  static const beaconFactsAdd = 'beacon.facts.add';
  static const beaconFactsComposerSubmit = 'beacon.facts.composer.submit';

  static const coordinationPromiseCreate = 'coordination.promise.create';
  static const coordinationComposerTitle = 'coordination.composer.title';
  static const coordinationComposerSubmit = 'coordination.composer.submit';

  static String coordinationItemMenu(String itemId) =>
      'coordination.item.$itemId.menu';
  static String coordinationItemResolve(String itemId) =>
      'coordination.item.$itemId.resolve';

  static String requestThread(String threadId) => 'request.thread.$threadId';

  static String helpOfferAccept(String userId) => 'help_offer.$userId.accept';
  static String helpOfferDecline(String userId) => 'help_offer.$userId.decline';
  static String helpOfferKeepStandby(String userId) =>
      'help_offer.$userId.keep_standby';
  static String helpOfferRemove(String userId) => 'help_offer.$userId.remove';
  static String helpOfferRelease(String userId) => 'help_offer.$userId.release';

  static const admissionReasonInput = 'help_offer.admission_reason.input';
  static const admissionReasonSubmit = 'help_offer.admission_reason.submit';
  static const helpOfferRoleLabelInput = 'help_offer.role_label.input';
  static const helpOfferRoleLabelSubmit = 'help_offer.role_label.submit';
  static String helpOfferRoleLabelEdit(String userId) =>
      'help_offer.$userId.role_label.edit';

  static const beaconOverflowMenu = 'beacon.overflow.menu';
  static const beaconOverflowClose = 'beacon.overflow.close';
  static const beaconOverflowRequestStatus = 'beacon.overflow.request_status';
  static const beaconOverflowActivity = 'beacon.overflow.activity';
  static const beaconOverflowAddPlan = 'beacon.overflow.add_plan';
  static const beaconCloseConfirm = 'beacon.close.confirm';

  /// Confirm action of the shared close-now sheet, shown from every author
  /// close-now entry (HUD, status sheet, My Work card CTA).
  static const beaconCloseNowConfirm = 'beacon.close_now.confirm';

  /// Status bottom-sheet row, keyed by [BeaconStatusMenuRowId.name].
  static String beaconStatusRow(String rowId) => 'beacon.status_row.$rowId';

  /// Author HUD primary action, keyed by [BeaconHudAuthorAction.name]
  /// (e.g. `wrapUpForReview`, `closeNow`).
  static String beaconHudAuthorAction(String action) =>
      'beacon.hud_author_action.$action';

  static const beaconHudMarkEnoughHelpConfirm =
      'beacon.hud.mark_enough_help.confirm';

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
  static const friendsTrustInfo = 'friends.trust_info';
  static const friendsMore = 'friends.more';

  static const constellationNavItem = 'constellation.nav_item';
  static const constellationAppBarViewModeMap =
      'constellation.app_bar.view_mode.map';
  static const constellationAppBarViewModeText =
      'constellation.app_bar.view_mode.text';
  static String constellationTextRequest(String requestId) =>
      'constellation.text.request.$requestId';
  static String constellationTemporaryOutline(String personId) =>
      'constellation.temporary_outline.$personId';
  static const constellationPinTarget = 'constellation.pin_target';
  static const constellationUnpinTarget = 'constellation.unpin_target';
  static const constellationFilterShowClosed =
      'constellation.filter.show_closed';
  static const constellationFilterParticipatedOnly =
      'constellation.filter.participated_only';
  static const constellationHiddenPinsCount = 'constellation.hidden_pins_count';
  static const constellationRequestStatusMarker =
      'constellation.request_status_marker';
  static const constellationPinMarker = 'constellation.pin_marker';
  static const constellationFitAll = 'constellation.camera.fit_all';
  static const constellationRearrange = 'constellation.camera.rearrange';
  static const constellationCenterOnMe = 'constellation.camera.center_on_me';
  static const myWorkFindWaysToHelp = 'my_work.find_ways_to_help';

  static const orientationPanel = 'orientation.panel';
  static const orientationDismiss = 'orientation.dismiss';

  static const debugOrientationAuto = 'debug.orientation.auto';
  static const debugOrientationShow = 'debug.orientation.show';
  static const debugOrientationHide = 'debug.orientation.hide';
  static const debugOrientationReset = 'debug.orientation.reset';

  static ValueKey<String> key(String id) => ValueKey<String>(id);
}
