import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/main.dart' as app;
import 'package:web/web.dart' as web;

import 'support/e2e_test_helpers.dart';

const _inspectionTab = 'post-link-inspection';

Future<void> main() async {
  // Keep the driver alive in the original tab while the other tab boots
  // the production app and goes through real document navigations.
  if (Uri.base.queryParameters.containsKey(_inspectionTab)) {
    await app.main();
    WidgetsBinding.instance.ensureSemantics();
    return;
  }

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a shared Post URL is replaced and survives a browser reload', (
    tester,
  ) async {
    await launchApp(app.main);
    final fixture = await bootstrapFixture(
      runId: uniqueRunId('post-detail-reload'),
    );
    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    final body = uniqueRequestTitle('Shared Post');
    final id = await createPublishedPost(
      body: body,
      recipientIds: [fixture.helperUserId],
    );

    Uri location(String document, String path) => Uri.parse(
      web.window.location.href,
    ).replace(queryParameters: {_inspectionTab: document}, fragment: path);
    final previous = location('previous', kPathConversations);
    final legacy = location('post', '/beacon/view/$id?is_deep_link=true');
    final popup = web.window.open(previous.toString(), '_blank');
    expect(popup, isNotNull, reason: 'Chrome should open the inspection tab');
    final tab = popup!;
    void closeInspectionTab() => tab.close();
    addTearDown(closeInspectionTab);

    await pumpUntil(
      tester,
      () => tab.document.querySelector('flt-semantics') != null,
      label: 'the preceding Conversations document to render',
    );
    final historyLength = tab.history.length;
    tab.location.assign(legacy.toString());
    bool showsPost() =>
        tab.location.search == '?$_inspectionTab=post' &&
        tab.document.querySelector('flt-semantics[aria-label*="$body"]') !=
            null;
    final canonical = '#/post/view/$id?is_deep_link=true';
    await pumpUntil(tester, showsPost, label: 'the shared Post to render');
    expect(tab.location.hash, canonical);
    expect(tab.history.length, historyLength + 1);

    const reloadMarker = 'data-before-post-reload';
    tab.document.documentElement!.setAttribute(reloadMarker, '');
    tab.location.reload();
    await pumpUntil(
      tester,
      () =>
          tab.document.documentElement?.hasAttribute(reloadMarker) == false &&
          showsPost(),
      label: 'the same Post to render in a new document after reload',
    );
    expect(tab.location.hash, canonical);

    tab.history.back();
    await pumpUntil(
      tester,
      () => tab.location.hash == '#$kPathConversations',
      label: 'Back to return to Conversations without visiting the old URL',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
