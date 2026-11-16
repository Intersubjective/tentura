// A copy whose source the viewer may no longer read (for example the user
// who pinned the source fact and was then removed from the source Request's
// chat): the server answers BeaconFactCardOrigin with the bare unavailable
// body. Over the real GraphQL transport, repository mapper and
// BeaconThreadsCase.factOrigin, tapping the origin line must show the
// «original isn't available» snackbar (beaconRoomFactOriginUnavailable),
// keep the router where it was (no source Request or Post with the
// focus-fact query) and leave the open sheet in place.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fact_origin_test_support.dart';

void main() {
  group('an unavailable origin answered over the real transport', () {
    testWidgets('tapping the origin line shows the unavailable snackbar, does '
        'not navigate and keeps the open sheet', (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final wire = (await tester.runAsync(
        () => OriginWire.start(
          origin: {
            'available': false,
            'beaconId': null,
            'factCardId': null,
            'beaconKind': null,
            'changedSinceCopy': null,
            'canSeeCopiedRevision': null,
            'copiedRevisionSeq': null,
          },
        ),
      ))!;
      addTearDown(() => tester.runAsync(wire.close));
      registerFactRepository(wire.repository);

      final router = await pumpOriginRouter(
        tester,
        openCopy: (ctx) => unawaited(
          showFactActionsHostSheet(
            ctx,
            fact: copiedFact(),
            canMutate: false,
            onCorrect:
                ({
                  required factCardId,
                  required newText,
                  attachmentsJson,
                }) async {},
            onRemove: ({required factCardId}) async {},
            onSetVisibility:
                ({required factCardId, required visibility}) async {},
          ),
        ),
      );
      final before = routerLocation(router);
      await tester.tap(find.text('open-copy'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.beaconRoomFactManageSheetTitle), findsOneWidget);

      await tapAndPumpRealAsync(tester, find.text(kOriginFromRequest));

      expect(wire.sent, contains('BeaconFactCardOrigin'));
      expect(
        find.text(l10n.beaconRoomFactOriginUnavailable, findRichText: true),
        findsOneWidget,
      );
      final after = routerLocation(router);
      expect(after, before);
      expect(after.queryParameters, isNot(contains(kQueryFocusFact)));
      expect(after.path, isNot(startsWith(kPathPostView)));
      expect(after.path, isNot(contains(kSourceBeaconId)));
      expect(find.textContaining('source-page:'), findsNothing);
      expect(find.text(kCopyPageMarker), findsOneWidget);
      // The actions sheet over the copy is still open.
      expect(find.text(l10n.beaconRoomFactManageSheetTitle), findsOneWidget);
    });
  });
}
