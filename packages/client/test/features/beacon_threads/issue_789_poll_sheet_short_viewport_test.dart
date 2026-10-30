import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_poll_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockRoomCubit extends Mock implements RoomCubit {}

Future<void> _openPollSheet(WidgetTester tester) async {
  const viewport = Size(375, 667);
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showBeaconRoomPollSheet(context, cubit: _MockRoomCubit()),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Rect _viewport(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

void _expectFullyVisible(WidgetTester tester, Finder finder) {
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  final view = _viewport(tester);
  expect(rect.top, greaterThanOrEqualTo(view.top));
  expect(rect.bottom, lessThanOrEqualTo(view.bottom + 0.5));
}

void main() {
  testWidgets('#789 Create poll actions stay visible at 375×667', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await _openPollSheet(tester);

    _expectFullyVisible(
      tester,
      find.widgetWithText(TextButton, l10n.buttonCancel),
    );
    _expectFullyVisible(
      tester,
      find.widgetWithText(FilledButton, l10n.beaconRoomSendPollButton),
    );
    expect(tester.takeException(), isNull);
  });
}
