import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/features/beacon_threads/ui/widget/post_root_pin_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/inbox/ui/screen/conversations_screen.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

const _fixtureTab = 'post-reply-inspection';
const _snapshotHook = 'postReplySnapshot';
const _actionHook = 'postReplyAction';
const _reloadHook = 'postReplyReload';
const _reloadMarker = 'data-post-reply-before-reload';
const _reloadProbeLoads = 'postReplyReloadProbeLoads';
const _draft = 'Draft reply 1105';
const _keep = 'Вернуться к заполнению';
const _discard = 'Выйти и сбросить';
const _dialog = 'Выйти без сохранения?';
final _input = find.byKey(TestIds.key(TestIds.roomMessageInput));
final _back = find.byType(BackButton);

Finder _postRoot(String body) => find.byWidgetPredicate(
  (widget) => widget is PostRootPinCard && widget.rootMessage?.body == body,
);

Finder _message(String body) => find.byWidgetPredicate(
  (widget) =>
      widget is RoomMessageTile &&
      widget.message.body == body &&
      !widget.message.id.startsWith('local:'),
);

// The driver stays in the original document. The inspection tab runs the
// production app and can reload without disconnecting the integration runner.
Future<void> _launchInspectionTab() async {
  await app.main();
  final binding = WidgetsBinding.instance..ensureSemantics();
  final controller = LiveWidgetController(binding);
  globalContext[_reloadHook] = (() {
    web.document.documentElement!.setAttribute(_reloadMarker, '');
    web.window.location.reload();
  }).toJS;

  globalContext[_snapshotHook] = ((JSString id) {
    final field = _input.evaluate().firstOrNull?.widget as TextField?;
    final view = binding.platformDispatcher.views.single;
    final size = view.physicalSize / view.devicePixelRatio;
    return jsonEncode({
      'width': size.width,
      'height': size.height,
      'body': field?.controller?.text,
      'stored': readBeaconRoomComposerDraft(id.toDart),
      'post':
          (find.byType(PostViewScreen).evaluate().firstOrNull?.widget
                  as PostViewScreen?)
              ?.id,
      'rootBody':
          (find.byType(PostRootPinCard).evaluate().firstOrNull?.widget
                  as PostRootPinCard?)
              ?.rootMessage
              ?.body,
      'posts': find.byType(ConversationsScreen).evaluate().isNotEmpty,
      'inbox': find.byType(InboxScreen).evaluate().isNotEmpty,
      'dialog': find.text(_dialog).evaluate().isNotEmpty,
      'sent': _message(_draft).evaluate().isNotEmpty,
    }).toJS;
  }).toJS;

  Future<void> act(String action, String value) async {
    final target = switch (action) {
      'type' => _input,
      'send' => find.bySemanticsIdentifier(TestIds.roomMessageSend),
      'back' => _back,
      'dialog' => find.text(value),
      _ => throw ArgumentError.value(action),
    };
    if (action == 'type') {
      controller.state<EditableTextState>(
          find.descendant(of: target, matching: find.byType(EditableText)),
        )
        ..requestKeyboard()
        ..updateEditingValue(
          TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          ),
        );
      return;
    }
    // Activate the rendered control through Flutter's browser accessibility
    // action. The reloaded tab runs its own app and has no WidgetTester.
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(deadline)) {
      await controller.pump(const Duration(milliseconds: 50));
      if (target.evaluate().isEmpty) continue;
      final node = controller.getSemantics(target.last);
      if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
        node.owner!.performAction(node.id, SemanticsAction.tap);
        return;
      }
    }
    throw StateError('The $action control has no tap action');
  }

  globalContext[_actionHook] = ((JSString action, JSString value) {
    return act(action.toDart, value.toDart)
        .timeout(const Duration(seconds: 5))
        .then<JSString?>(
          (_) => null,
          onError: (Object error, StackTrace stack) => '$error\n$stack'.toJS,
        )
        .toJS;
  }).toJS;
}

enum _ReloadStage {
  unsentReply('reloading the unsent reply'),
  beforeVisitingAnotherPost('reloading before visiting another Post'),
  afterSend('reloading after send'),
  afterDiscard('reloading after confirmed discard'),
  whitespace('reloading whitespace-only text'),
  legacyLink('reloading a fresh legacy deep link'),
  canonicalUrl('reloading a fresh canonical URL');

  const _ReloadStage(this.description);

  final String description;
}

class _InspectionTab {
  _InspectionTab(this.tab, this.titles);

  final web.Window tab;
  final Map<String, String> titles;

  Map<String, dynamic> snapshot(String id) {
    final hook = tab.getProperty<JSFunction?>(_snapshotHook.toJS);
    final result = hook?.callAsFunction(null, id.toJS) as JSString?;
    if (result == null) return {};
    return jsonDecode(result.toDart) as Map<String, dynamic>;
  }

  Future<void> waitInTab(
    bool Function() condition, {
    required String label,
    Duration limit = const Duration(seconds: 60),
  }) async {
    // The opener is a background tab while the inspection tab renders.
    // Poll the document without asking the opener to produce a frame.
    final deadline = DateTime.now().add(limit);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      // Flutter draws no frames in a hidden tab, so keep the popup in front.
      tab.focus();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException(
      'Timed out waiting for $label at ${tab.location.hash}',
    );
  }

  Future<void> waitForPost(
    String id,
    String stage, {
    Duration limit = const Duration(seconds: 60),
  }) async {
    try {
      await waitInTab(
        () {
          final state = snapshot(id);
          return state['post'] == id &&
              state['body'] != null &&
              state['rootBody'] == titles[id];
        },
        label: 'Post $id and its reply composer to load ($stage)',
        limit: limit,
      );
    } on TimeoutException {
      fail(
        'Post $id did not load ($stage) at ${tab.location.hash}: ${snapshot(id)} closed=${tab.closed} ready=${tab.document.readyState} hook=${tab.getProperty<JSAny?>(_snapshotHook.toJS) != null} body=${tab.document.body?.innerText}',
      );
    }
  }

  Future<void> reload(
    String id,
    _ReloadStage stage, {
    Duration readinessLimit = const Duration(seconds: 60),
  }) async {
    tab.callMethod<JSAny?>(_reloadHook.toJS);
    await waitInTab(() {
      final document = tab.getProperty<web.Document?>('document'.toJS);
      return document?.documentElement?.hasAttribute(_reloadMarker) == false;
    }, label: 'a fresh browser document after ${stage.description}');
    await waitForPost(id, stage.description, limit: readinessLimit);
  }
}

void runPostReplyReloadStageFailureTest() {
  const postId = 'post-under-inspection';
  const title = 'Post under inspection';
  final readySnapshot = jsonEncode({
    'post': postId,
    'body': _draft,
    'rootBody': title,
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Each unready Post reload fails its own stage after one document load',
    (
      tester,
    ) async {
      // Count documents as they load, before any framework code could run.
      // The first reload has no Post. A retry would show the expected Post.
      final html =
          '''
<!doctype html>
<script>
  const loads = Number(sessionStorage.getItem('$_reloadProbeLoads') ?? -1) + 1;
  sessionStorage.setItem('$_reloadProbeLoads', String(loads));
  window.$_snapshotHook = () => loads === 1 ? '{}' : JSON.stringify($readySnapshot);
  window.$_reloadHook = () => {
    document.documentElement.setAttribute('$_reloadMarker', '');
    location.reload();
  };
</script>
''';
      final url = web.URL.createObjectURL(
        web.Blob([html.toJS].toJS, web.BlobPropertyBag(type: 'text/html')),
      );
      addTearDown(() => web.URL.revokeObjectURL(url));
      final tab = web.window.open(url, '_blank');
      if (tab == null) fail('Chrome could not open the inspection tab');
      addTearDown(() async => tab.close());
      final inspection = _InspectionTab(tab, {postId: title});
      await inspection.waitForPost(postId, 'opening the probe tab');

      expect(_ReloadStage.values, hasLength(7));
      for (final stage in _ReloadStage.values) {
        tab.sessionStorage.setItem(_reloadProbeLoads, '0');
        await expectLater(
          inspection
              .reload(
                postId,
                stage,
                readinessLimit: const Duration(seconds: 2),
              )
              .timeout(const Duration(seconds: 45)),
          throwsA(
            isA<TestFailure>().having(
              (error) => error.toString(),
              'readiness error',
              contains(stage.description),
            ),
          ),
          reason: stage.description,
        );
        expect(
          tab.sessionStorage.getItem(_reloadProbeLoads),
          '1',
          reason: 'Document loads while ${stage.description}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> main() async {
  if (Uri.base.queryParameters.containsKey(_fixtureTab)) {
    await _launchInspectionTab();
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Post replies stay with their Post across browser reloads', (
    tester,
  ) async {
    await launchApp(app.main);
    final fixture = await bootstrapFixture(runId: uniqueRunId('reply-reload'));
    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    await GetIt.I<SettingsCubit>().setLocalePreference(kLocalePreferenceRu);

    final titleA = uniqueRequestTitle('Post A');
    final titleB = uniqueRequestTitle('Post B');
    final postA = await createPublishedPost(
      body: titleA,
      recipientIds: [fixture.helperUserId],
    );
    final postB = await createPublishedPost(
      body: titleB,
      recipientIds: [fixture.helperUserId],
    );

    final observed = <String, Object?>{};
    final expected = <String, Object?>{};
    void check(String label, Object? actual, Object? wanted) {
      observed[label] = actual;
      expected[label] = wanted;
    }

    Uri url(String path) => Uri.parse(web.window.location.href).replace(
      queryParameters: {_fixtureTab: '1'},
      fragment: path,
    );
    final legacy = '$kPathBeaconView/$postA?is_deep_link=true';
    final canonical = '$kPathPostView/$postA';
    final titles = {postA: titleA, postB: titleB};
    web.Window openInspectionTab(String path) {
      final popup = web.window.open(
        url(path).toString(),
        '_blank',
        'popup,width=375,height=667',
      );
      expect(popup, isNotNull, reason: 'Chrome should open the inspection tab');
      final opened = popup!;
      addTearDown(() async => opened.close());
      return opened;
    }

    final tab = openInspectionTab(canonical);
    final inspection = _InspectionTab(tab, titles);
    final snapshot = inspection.snapshot;
    final waitInTab = inspection.waitInTab;
    final waitForPost = inspection.waitForPost;
    final reload = inspection.reload;

    var coldStarts = 0;
    // A full document load in the same popup: no history, a fresh app, and no
    // popup open/close cycle (a closed popup can leave the next one unbooted).
    Future<void> coldStart(String path) async {
      final target = url(path).replace(
        queryParameters: {_fixtureTab: '1', 'cold': '${++coldStarts}'},
      );
      tab.document.documentElement!.setAttribute(_reloadMarker, '');
      tab.location.replace(target.toString());
      await waitInTab(() {
        final document = tab.getProperty<web.Document?>('document'.toJS);
        return document?.documentElement?.hasAttribute(_reloadMarker) == false;
      }, label: 'a fresh browser document for $path');
    }

    Future<void> open(String path, String id) async {
      tab.location.hash = path;
      await waitForPost(id, 'after opening $path');
    }

    Future<void> act(String action, [String value = '']) async {
      final error = await tab
          .callMethod<JSPromise<JSString?>>(
            _actionHook.toJS,
            action.toJS,
            value.toJS,
          )
          .toDart
          .timeout(const Duration(seconds: 6));
      if (error != null) {
        fail('Could not $action in ${tab.location.hash}: ${error.toDart}');
      }
    }

    void checkDraft(String label, String id, String? text) {
      final state = snapshot(id);
      check('$label in the composer', state['body'], text ?? '');
      check('$label in the draft store', state['stored'], text);
    }

    bool returnedHome() =>
        snapshot(postA)['post'] == null &&
        snapshot(postA)['posts'] == true &&
        tab.location.hash.startsWith('#/home/');

    Future<void> waitForBackOutcome() => waitInTab(
      () => snapshot(postA)['dialog'] == true || returnedHome(),
      label: 'the discard dialog or a return to Home',
    );

    await waitForPost(postA, 'fresh canonical Post URL');
    expect(tab.location.hash, '#$canonical');
    expect(
      tab.history.length,
      1,
      reason: 'the canonical URL was opened directly',
    );
    expect(snapshot(postA)['body'], isEmpty);
    await act('back');
    await waitForBackOutcome();
    check(
      'Back from a fresh canonical URL opens Posts without a dialog',
      [tab.location.hash, snapshot(postA)['posts'], snapshot(postA)['dialog']],
      ['#$kPathConversations', true, false],
    );

    await coldStart(legacy);
    await waitForPost(postA, 'initial deep link');
    final initial = snapshot(postA);
    expect(initial['width'], 375);
    await act('type', _draft);
    expect(snapshot(postA)['body'], _draft);
    expect(snapshot(postA)['stored'], _draft);
    await reload(postA, _ReloadStage.unsentReply);
    checkDraft('reload restores the original reply', postA, _draft);
    await act('back');
    await waitForBackOutcome();
    final asked = snapshot(postA)['dialog'] == true;
    check('Back after reload asks before discarding', asked, true);
    if (asked) {
      await act('dialog', _keep);
      await waitForPost(postA, 'after Keep editing');
      await waitInTab(
        () => snapshot(postA)['dialog'] == false,
        label: 'Keep editing closes the discard dialog',
      );
    }
    checkDraft('keep editing preserves the reply', postA, _draft);

    await open(canonical, postA);
    await act('type', 'Draft A');
    expect(snapshot(postA)['stored'], 'Draft A');
    await reload(postA, _ReloadStage.beforeVisitingAnotherPost);
    await open('$kPathPostView/$postB', postB);
    checkDraft('another Post starts empty', postB, null);
    await open(canonical, postA);
    checkDraft(
      'returning to the first Post restores its reply',
      postA,
      'Draft A',
    );

    await act('type', _draft);
    expect(snapshot(postA)['stored'], _draft);
    await act('send');
    await waitInTab(
      () => snapshot(postA)['sent'] == true,
      label: 'the server-confirmed reply to appear',
    );
    await reload(postA, _ReloadStage.afterSend);
    checkDraft('sending clears the reply draft', postA, null);

    await act('type', 'Discard this reply');
    expect(snapshot(postA)['stored'], 'Discard this reply');
    await act('back');
    await waitInTab(
      () => snapshot(postA)['dialog'] == true,
      label: 'the draft discard dialog',
    );
    await act('dialog', _discard);
    await waitInTab(
      () => snapshot(postA)['dialog'] == false && returnedHome(),
      label: 'Home after confirming discard',
    );
    check(
      'confirmed discard returns to Posts',
      tab.location.hash,
      '#$kPathConversations',
    );
    await open(canonical, postA);
    checkDraft('reopening shows the discarded reply is gone', postA, null);
    await reload(postA, _ReloadStage.afterDiscard);
    checkDraft('reloading keeps the discarded reply cleared', postA, null);

    await act('type', '   ');
    expect(snapshot(postA)['body'], '   ');
    await reload(postA, _ReloadStage.whitespace);
    checkDraft('whitespace is absent after reload', postA, null);
    await act('back');
    await waitForBackOutcome();
    check(
      'Back with a blank reply skips confirmation',
      snapshot(postA)['dialog'],
      false,
    );
    check(
      'Back from a cold Post opens Posts',
      [tab.location.hash, snapshot(postA)['posts']],
      ['#$kPathConversations', true],
    );

    // Fresh tabs have no in-app history: after a reload, confirming the
    // discard must still land on Posts.
    for (final (label, path, stage) in [
      ('legacy deep link', legacy, _ReloadStage.legacyLink),
      ('canonical URL', canonical, _ReloadStage.canonicalUrl),
    ]) {
      await coldStart(path);
      await waitForPost(postA, 'fresh $label');
      await act('type', _draft);
      await reload(postA, stage);
      checkDraft('$label reload restores the reply', postA, _draft);
      await act('back');
      await waitInTab(
        () => snapshot(postA)['dialog'] == true,
        label: 'the discard dialog after reloading a $label',
      );
      await act('dialog', _discard);
      await waitInTab(
        () => snapshot(postA)['dialog'] == false && returnedHome(),
        label: 'Home after confirming discard on a reloaded $label',
      );
      check(
        'confirmed discard after reloading a $label lands on Posts',
        [tab.location.hash, snapshot(postA)['posts']],
        ['#$kPathConversations', true],
      );
    }

    // Opened from the Posts tab (phone-width tab: the driver is too wide for
    // an in-app Back button).
    await coldStart(kPathConversations);
    await waitInTab(
      () => snapshot(postA)['posts'] == true,
      label: 'the Posts root',
    );
    await act('dialog', titleA);
    await waitForPost(postA, 'opened from Posts');
    await act('back');
    await waitForBackOutcome();
    check(
      'Back from a Post with an empty reply returns directly to Posts',
      [tab.location.hash, snapshot(postA)['posts'], snapshot(postA)['dialog']],
      ['#$kPathConversations', true, false],
    );
    await act('dialog', titleA);
    await waitForPost(postA, 'reopened from Posts');
    await act('type', _draft);
    await act('back');
    await waitInTab(
      () => snapshot(postA)['dialog'] == true,
      label: 'the discard dialog from Posts',
    );
    await act('dialog', _discard);
    await waitInTab(returnedHome, label: 'Posts after discard');
    check(
      'Back from a Post opened in Posts restores its URL and root',
      [tab.location.hash, snapshot(postA)['posts']],
      ['#$kPathConversations', true],
    );

    // A reply by the recipient creates the Post's entry in the author's Activity.
    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await goToDeepLink(tester, '$kPathBeaconView/$postB');
    await pumpUntilVisible(tester, _postRoot(titleB));
    await sendRoomMessage(tester, 'Reply from the recipient');
    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    await goToPath(tester, kPathInbox);
    await coldStart(kPathInbox);
    await waitInTab(
      () => snapshot(postB)['inbox'] == true,
      label: 'the Activity root',
    );
    await act('dialog', titleB);
    await waitForPost(postB, 'opened from Activity');
    await act('back');
    await waitInTab(
      () => snapshot(postB)['post'] == null && snapshot(postB)['inbox'] == true,
      label: 'Activity after Back',
    );
    check(
      'Back from a Post opened in Activity restores its URL and root',
      [tab.location.hash, snapshot(postB)['inbox']],
      ['#$kPathInbox', true],
    );

    expect(observed, expected);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
