import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/navigation/home_tab.dart';

/// One recorded [AppNavigator] call: the method name and the arguments the
/// caller passed (null and default-valued arguments are left out).
@immutable
final class NavIntent {
  const NavIntent(this.method, [this.args = const {}]);

  final String method;
  final Map<String, Object?> args;

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      other is NavIntent &&
      other.method == method &&
      _equality.equals(other.args, args);

  @override
  int get hashCode => Object.hash(method, _equality.hash(args));

  @override
  String toString() => args.isEmpty ? '$method()' : '$method($args)';
}

/// Records navigation intents instead of navigating, for widget tests of
/// feature UI that navigates through [AppNavigator].
///
/// Register it with [registerFakeAppNavigator]; assert on [intents].
class FakeAppNavigator implements AppNavigator {
  final intents = <NavIntent>[];

  /// Returned by [rootContext]; tests that open root dialogs set it.
  BuildContext? context;

  void _record(String method, [Map<String, Object?> args = const {}]) =>
      intents.add(
        NavIntent(method, {
          for (final e in args.entries)
            if (e.value != null &&
                e.value != '' &&
                !(e.value is Iterable && (e.value! as Iterable).isEmpty) &&
                !(e.value is Map && (e.value! as Map).isEmpty))
              e.key: e.value,
        }),
      );

  /// The recorded intents with [method], in call order.
  List<NavIntent> named(String method) =>
      intents.where((i) => i.method == method).toList(growable: false);

  @override
  BuildContext? get rootContext => context;

  /// Returned by [activeHomeTabIndex].
  int? homeTabIndex;

  @override
  int? get activeHomeTabIndex => homeTabIndex;

  @override
  Future<void> openHomeTab(HomeTab tab) async =>
      _record('openHomeTab', {'tab': tab});

  @override
  Future<void> openMyProfile() async => _record('openMyProfile');

  @override
  Future<void> openBeacon(
    String id, {
    String? entry,
    String? viewTab,
    String? threadId,
    String? messageId,
    String? peopleTabAttention,
  }) async => _record('openBeacon', {
    'id': id,
    'entry': entry,
    'viewTab': viewTab,
    'threadId': threadId,
    'messageId': messageId,
    'peopleTabAttention': peopleTabAttention,
  });

  @override
  Future<void> navigateToBeacon(String id, {String? entry}) async =>
      _record('navigateToBeacon', {'id': id, 'entry': entry});

  @override
  Future<void> openBeaconLobby(String beaconId) async =>
      _record('openBeaconLobby', {'beaconId': beaconId});

  @override
  Future<void> forwardBeacon(String beaconId, {String? tags}) async =>
      _record('forwardBeacon', {'beaconId': beaconId, 'tags': tags});

  @override
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
  }) async => _record('createBeacon', {
    'draftId': draftId,
    'editId': editId,
    'initialTab': initialTab,
    'forwardToUserId': forwardToUserId,
    'parentBeaconId': parentBeaconId,
    'sourceMessageId': sourceMessageId,
    'forkSourceId': forkSourceId,
    'forkPlanTimes': forkPlanTimes,
    'initialRecipientIds': initialRecipientIds,
    'initialNotes': initialNotes,
    'onRecipientsChanged': onRecipientsChanged,
    'onPublished': onPublished,
  });

  @override
  Future<void> createPost({
    String draftId = '',
    String forwardToUserId = '',
    Set<String> initialRecipientIds = const {},
    void Function(Set<String>, Map<String, String>)? onRecipientsChanged,
    VoidCallback? onPublished,
  }) async => _record('createPost', {
    'draftId': draftId,
    'forwardToUserId': forwardToUserId,
    'initialRecipientIds': initialRecipientIds,
    'onRecipientsChanged': onRecipientsChanged,
    'onPublished': onPublished,
  });

  @override
  Future<void> openProfile(String id) async =>
      _record('openProfile', {'id': id});

  @override
  Future<void> openPeopleTags() async => _record('openPeopleTags');

  @override
  Future<void> openInboxWatching({String? highlightBeaconId}) async =>
      _record('openInboxWatching', {'highlightBeaconId': highlightBeaconId});

  @override
  Future<void> openInboxWatchingFromHome(String beaconId) async =>
      _record('openInboxWatchingFromHome', {'beaconId': beaconId});

  /// Records the receipt's id.
  @override
  Future<void> openFromUpdate(AttentionReceipt receipt) async =>
      _record('openFromUpdate', {'receipt': receipt.id});

  @override
  Future<void> openInvitations() async => _record('openInvitations');

  @override
  Future<void> openBlockedUsers() async => _record('openBlockedUsers');

  @override
  Future<void> openRecover() async => _record('openRecover');

  @override
  Future<void> resetToRecover() async => _record('resetToRecover');

  @override
  Future<void> resetToLogin() async => _record('resetToLogin');

  @override
  Future<void> openPath(String path) async =>
      _record('openPath', {'path': path});

  @override
  Future<void> popOrGoHome([Object? result]) async =>
      _record('popOrGoHome', {'result': result});

  @override
  void back() => _record('back');
}

/// Registers a fresh [FakeAppNavigator] as the [AppNavigator] for this test
/// (replacing any registered one) and unregisters it on tear-down.
FakeAppNavigator registerFakeAppNavigator() {
  final navigator = FakeAppNavigator();
  final getIt = GetIt.I;
  if (getIt.isRegistered<AppNavigator>()) {
    // No dispose callback is registered, so this completes synchronously.
    final unregistered = getIt.unregister<AppNavigator>();
    assert(unregistered is! Future, 'AppNavigator unregistered async');
  }
  getIt.registerSingleton<AppNavigator>(navigator);
  addTearDown(() async {
    if (getIt.isRegistered<AppNavigator>(instance: navigator)) {
      await getIt.unregister<AppNavigator>(instance: navigator);
    }
  });
  return navigator;
}
