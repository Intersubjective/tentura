import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/evaluation/domain/entity/review_window_info.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _FakeEvaluationRepository extends Mock implements EvaluationRepository {
  int closeCalls = 0;

  @override
  Future<ReviewWindowInfo> fetchReviewWindowStatus(String beaconId) async =>
      ReviewWindowInfo(
        beaconId: beaconId,
        hasWindow: true,
        canCloseNow: true,
        unsentStartedPackages: 3,
      );

  @override
  Future<BeaconLifecycleMutationResult> beaconCloseNow(String beaconId) {
    closeCalls++;
    throw UnimplementedError();
  }
}

void main() {
  final l10n = lookupL10n(const Locale('en'));

  testWidgets('My Work close shows the close confirm before closing', (
    tester,
  ) async {
    final repo = _FakeEvaluationRepository();

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (ctx) {
                context = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );

    final result = myWorkConfirmCloseNow(
      context: context,
      beaconId: 'b1',
      evaluationRepository: repo,
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconReviewCloseNowBody), findsOneWidget);
    expect(
      find.text(l10n.beaconReviewCloseNowDiscardNote(3)),
      findsOneWidget,
    );
    expect(repo.closeCalls, 0);

    await tester.tap(find.text(l10n.buttonCancel));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(repo.closeCalls, 0);
  });
}
