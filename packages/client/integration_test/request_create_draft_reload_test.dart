import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('request create draft survives hard reload via draft_id URL', (
    tester,
  ) async {
    await launchApp(app.main);
    await pumpSettleBounded(tester);

    final fixture = await bootstrapFixture(
      runId: uniqueRunId('draft-reload'),
    );
    final title = uniqueRequestTitle('IT draft reload');
    const description =
        'Integration test description long enough for quiet autosave.';

    await loginAs(tester, fixture.authorEmail);
    await goToPath(tester, kPathBeaconNew);

    final titleField = find.byKey(TestIds.key(TestIds.requestTitle));
    await pumpUntilVisible(tester, titleField);
    await tester.tap(titleField);
    await tester.enterText(titleField, title);
    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestDescription)),
      description,
    );
    syncBeaconCreateDraftFields(
      tester,
      title: title,
      description: description,
    );

    final formBody = find.byKey(const Key('BeaconCreate.FormBody'));
    await pumpUntilVisible(tester, formBody);
    final cubit = tester.element(formBody).read<BeaconCreateCubit>();
    await cubit.flushAutosave();
    await pumpUntil(
      tester,
      () => cubit.state.draftId?.isNotEmpty ?? false,
      label: 'draft id before simulated reload',
      timeout: const Duration(seconds: 30),
    );

    final draftId = cubit.state.draftId!;
    final href = web.window.location.href;
    expect(
      href,
      contains('$kQueryBeaconDraftId=$draftId'),
      reason: 'autosave must stamp draft_id into the browser URL',
    );

    await goToPath(
      tester,
      '$kPathBeaconNew?$kQueryBeaconDraftId=$draftId',
    );
    await pumpSettleBounded(tester);

    expect(find.text(title), findsWidgets);
    expect(find.text(description), findsWidgets);
  });
}
