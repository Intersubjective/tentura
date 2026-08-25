import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'witness admission gates the forward band; mute removes it (G3b)',
    (tester) async {
      await launchApp(app.main);
      await tester.pumpAndSettle();

      final runId = uniqueRunId('g3b');
      final fixture = await bootstrapWitnessFixture(runId: runId);

      final requestTitle = uniqueRequestTitle('IT G3b witness');
      final legacyFixture = IntegrationFixture(
        authorEmail: fixture.bobEmail,
        authorUserId: fixture.bobUserId,
        helperEmail: fixture.carolEmail,
        helperUserId: fixture.carolUserId,
      );

      await logout(tester);
      await createAndForwardRequest(
        tester,
        fixture: legacyFixture,
        title: requestTitle,
        needSlug: 'transport',
      );

      await logout(tester);
      await offerHelpFromInbox(
        tester,
        fixture: legacyFixture,
        requestTitle: requestTitle,
        capabilitySlug: 'transport',
      );

      await logout(tester);
      await acceptHelpOffer(
        tester,
        fixture: legacyFixture,
        requestTitle: requestTitle,
      );

      await closeRequestAndOpenReview(tester);
      await reviewParticipant(
        tester,
        fixture.carolUserId,
        impact: 'pos1',
        ackTags: const ['transport'],
      );
      // The outer `evaluationSubmit` button on review_contributions_screen
      // (distinct from the per-participant sheet's `evaluationSave`) calls
      // EvaluationCubit.finalize(), which server-side only marks THIS
      // reviewer's (Bob's) own review status as done (`evaluationFinalize`
      // — verified server-side, `beacon_review_status.status` → 2) and
      // navigates back on success. It does NOT itself close/finalize the
      // beacon or write capability evidence — that is the separate,
      // explicit author action `EvaluationCase.closeNow` →
      // `ReviewFinalizationCase.closeAndFinalize`, exposed client-side as
      // `BeaconViewCubit.closeBeaconNow()` behind the beacon-detail HUD's
      // `closeNow` action (gated by `_canCloseNow`: all required reviewers
      // finished or skipped — satisfied once Bob's own review is done).
      await tapAndSettle(
        tester,
        find.byKey(TestIds.key(TestIds.evaluationSubmit)),
      );

      // `_canCloseNow` (evaluation_case.dart) requires EVERY author/committer
      // participant's own review status to independently reach finished(2)
      // or skipped(3) — Bob's evaluationSubmit only set HIS status. Carol
      // (the committer) has nothing useful to evaluate here, so she uses the
      // review screen's real "Skip for now" affordance, reached via her own
      // My Work card's "Review" quick action (`showReviewCta`).
      await logout(tester);
      await loginAs(tester, fixture.carolEmail);
      await goToPath(tester, kPathMyWork);
      final reviewCta = find.text('Review');
      await pumpUntilVisible(
        tester,
        reviewCta,
        timeout: const Duration(seconds: 30),
      );
      await tapAndSettle(tester, reviewCta.first);
      await tapAndSettle(tester, find.text('Skip for now'));

      // Switch back to Bob — only the beacon author may trigger closeNow.
      await logout(tester);
      await loginAs(tester, fixture.bobEmail);
      await triggerCloseNow(tester);

      // Alice explicitly trusts Bob (one-way): a fresh request of her own
      // that needs `transport` must surface Carol in the forward band with
      // network-outcome evidence, since finalization just wrote Bob's
      // close-acknowledgement for Carol on that tag and Alice admits Bob.
      await logout(tester);
      await createRequestReachRecipientsTab(
        tester,
        viewerEmail: fixture.aliceEmail,
        title: uniqueRequestTitle('IT G3b alice view'),
        needSlug: 'transport',
      );
      await pumpUntilVisible(
        tester,
        find.textContaining('Seen helping with'),
        timeout: const Duration(seconds: 60),
      );

      // Eve does not trust Bob and does not clear her own eligibility floor
      // for him — the same evidence must not surface in her band.
      await logout(tester);
      await createRequestReachRecipientsTab(
        tester,
        viewerEmail: fixture.eveEmail,
        title: uniqueRequestTitle('IT G3b eve view'),
        needSlug: 'transport',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Seen helping with'), findsNothing);

      // Carol mutes `transport` via the real F5 settings screen — Alice's
      // band must lose the evidence even though Bob's acknowledgement and
      // Alice's admission of Bob are both unchanged.
      await logout(tester);
      await loginAs(tester, fixture.carolEmail);
      await toggleRoutingMute(
        tester,
        capabilityLabel: 'Transport',
        groupLabel: 'Logistics',
      );

      await logout(tester);
      await createRequestReachRecipientsTab(
        tester,
        viewerEmail: fixture.aliceEmail,
        title: uniqueRequestTitle('IT G3b alice after mute'),
        needSlug: 'transport',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Seen helping with'), findsNothing);
    },
  );
}
