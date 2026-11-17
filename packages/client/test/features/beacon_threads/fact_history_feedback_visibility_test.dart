import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fact_sheet_feedback.dart';
import '../../support/phone_surface.dart';
import 'fact_origin_test_support.dart';

class _RestoreFailureRepository extends FakeOriginFactCardRepository {
  _RestoreFailureRepository() : super(historyLength: 2);

  @override
  Future<int> restore({
    required String beaconId,
    required String factCardId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) async => throw StateError('offline');
}

class _RestoreSuccessRepository extends FakeOriginFactCardRepository {
  _RestoreSuccessRepository() : super(historyLength: 2);

  int restoreCalls = 0;

  @override
  Future<int> restore({
    required String beaconId,
    required String factCardId,
    required int fromSeq,
    required int baseRevisionSeq,
  }) async => ++restoreCalls + 2;
}

void main() {
  group('phone feedback from fact history', () {
    setUp(registerPhoneFeedbackLogger);
    testWidgets('an unavailable source is visible above the history sheet', (
      tester,
    ) async {
      final repo = FakeOriginFactCardRepository(historyLength: 1);
      registerFactRepository(repo);
      await usePhoneSurface(tester);
      await pumpOpener(
        tester,
        size: kPhoneSurface,
        open: (ctx) => unawaited(
          showFactHistorySheet(
            ctx,
            beaconId: kCopyBeaconId,
            factCardId: kCopyFactId,
            baseRevisionSeq: 1,
            canMutate: false,
            originBeaconKind: 0,
            repository: repo,
          ),
        ),
      );
      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.ensureVisible(
        find.text(l10n.beaconRoomFactHistoryOpenOrigin),
      );
      await tester.tap(find.text(l10n.beaconRoomFactHistoryOpenOrigin));
      await tester.pumpAndSettle();
      expectPhoneFeedback(tester, "The original isn't available to you");
    });

    testWidgets('a restore confirmation is visible above the history sheet', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final repo = _RestoreSuccessRepository();
      registerFactRepository(repo);
      await pumpOpener(
        tester,
        size: kPhoneSurface,
        open: (ctx) => unawaited(
          showFactHistorySheet(
            ctx,
            beaconId: kCopyBeaconId,
            factCardId: kCopyFactId,
            baseRevisionSeq: 2,
            canMutate: true,
            repository: repo,
          ),
        ),
      );
      final restore = find.text('Restore this version').last;
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(repo.restoreCalls, 1);
      expectPhoneFeedback(tester, 'Restored an earlier version');
    });

    testWidgets('a failed restore is visible above the history sheet', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final repo = _RestoreFailureRepository();
      registerFactRepository(repo);
      await pumpOpener(
        tester,
        size: kPhoneSurface,
        open: (ctx) => unawaited(
          showFactHistorySheet(
            ctx,
            beaconId: kCopyBeaconId,
            factCardId: kCopyFactId,
            baseRevisionSeq: 2,
            canMutate: true,
            repository: repo,
          ),
        ),
      );
      final restore = find.text('Restore this version').last;
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expectPhoneFeedback(tester, 'Could not restore this version');
    });
  });
}
