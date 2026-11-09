import 'package:flutter/widgets.dart';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';

import 'home_tab.dart';

/// Presentation-layer navigation port: one method per navigation intent.
///
/// Feature UI navigates through this port instead of building route classes,
/// so it never imports `lib/app/router/` (whose generated routes reach every
/// screen and would put the whole app in each feature's import closure).
/// `RootRouter` implements it; get it with `GetIt.I<AppNavigator>()`, looked
/// up when the navigation happens (not in `build`), so widget tests register
/// `FakeAppNavigator` only when they tap through.
///
/// Keep this file a leaf: Dart, Flutter and leaf domain types only. An import
/// of a feature or `lib/app/` file brings the cycle back through the port.
///
/// Each method keeps the stack semantics its call sites had: "push" adds the
/// page above the current one on the root stack (the route lives there, so
/// pushing from a nested router lands on the root too), "navigate" returns to
/// the page when it is already on the stack, "reset" replaces the whole stack.
abstract interface class AppNavigator {
  /// The root navigator's context, for dialogs opened outside any route.
  BuildContext? get rootContext;

  /// The active tab index of Home's tabs router; null while Home has no
  /// mounted tabs.
  int? get activeHomeTabIndex;

  /// Shows Home's [tab] and replaces the URL with the tab's path.
  Future<void> openHomeTab(HomeTab tab);

  /// Opens Home's Me tab, from inside Home or from a route pushed above it
  /// (the URL changes only when Home is not the current root route).
  Future<void> openMyProfile();

  /// Pushes the Request detail (`BeaconViewRoute`).
  Future<void> openBeacon(
    String id, {
    String? entry,
    String? viewTab,
    String? threadId,
    String? messageId,
    String? peopleTabAttention,
  });

  /// Navigates to the Request detail (`navigate`: pops back to it when it is
  /// already on the stack, pushes it otherwise).
  Future<void> navigateToBeacon(String id, {String? entry});

  /// Pushes a Request's Questions (internally the lobby).
  Future<void> openBeaconLobby(String beaconId);

  /// Pushes the forward flow for a Request.
  Future<void> forwardBeacon(String beaconId, {String? tags});

  /// Pushes the Request composer (new, draft, edit, child, fork).
  Future<void> createBeacon({
    String draftId = '',
    String editId = '',
    String initialTab = '',
    String forwardToUserId = '',
    String parentBeaconId = '',
    String sourceMessageId = '',
    String forkSourceId = '',
    String forkPlanTimes = '',
    Set<String> initialRecipientIds = const {},
    Map<String, String> initialNotes = const {},
    void Function(Set<String>, Map<String, String>)? onRecipientsChanged,
    VoidCallback? onPublished,
  });

  /// Pushes the Post composer.
  Future<void> createPost({
    String draftId = '',
    String forwardToUserId = '',
    Set<String> initialRecipientIds = const {},
    void Function(Set<String>, Map<String, String>)? onRecipientsChanged,
    VoidCallback? onPublished,
  });

  /// Pushes another person's profile on the root stack.
  Future<void> openProfile(String id);

  /// Pushes the people tags list.
  Future<void> openPeopleTags();

  /// Pushes Activity's Watching list, optionally highlighting a Request.
  Future<void> openInboxWatching({String? highlightBeaconId});

  /// Resets the stack to Home's Activity tab, then pushes Watching with
  /// [beaconId] highlighted.
  Future<void> openInboxWatchingFromHome(String beaconId);

  /// Opens the destination of an Updates row (see `RootRouter`).
  Future<void> openFromUpdate(AttentionReceipt receipt);

  /// Opens Network's Invitations tab (see `RootRouter`).
  Future<void> openInvitations();

  /// Opens Network's Blocked people (see `RootRouter`).
  Future<void> openBlockedUsers();

  /// Pushes seed recovery.
  Future<void> openRecover();

  /// Replaces the whole stack with seed recovery.
  Future<void> resetToRecover();

  /// Replaces the whole stack with the sign-in screen.
  Future<void> resetToLogin();

  /// Pushes [path] on the root stack, prefix matches allowed; a path that
  /// does not resolve is logged, not thrown.
  Future<void> openPath(String path);

  /// Pops the top root route with [result], or replaces the stack with Home
  /// when nothing can pop.
  Future<void> popOrGoHome([Object? result]);

  /// Pops the root router's top route (`StackRouter.back`).
  void back();
}
