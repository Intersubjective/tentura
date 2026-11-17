import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phone_surface.dart';

/// Text must receive a hit through the actual modal stack, not merely be
/// mounted in the ScaffoldMessenger below an opaque sheet or its barrier.
void expectPhoneFeedback(WidgetTester tester, String message) {
  final text = find.text(message, findRichText: true);
  expect(text, findsOneWidget, reason: 'the action must produce feedback');
  expect(
    text.hitTestable(),
    findsOneWidget,
    reason: 'feedback must be above the fact sheet and modal barrier',
  );
  final rect = tester.getRect(text);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(kPhoneSurface.width));
  expect(rect.bottom, lessThanOrEqualTo(kPhoneSurface.height));
  expect(tester.takeException(), isNull);
}

void registerPhoneFeedbackLogger() {
  if (GetIt.I.isRegistered<Logger>()) return;
  GetIt.I.registerSingleton<Logger>(Logger('fact sheet feedback'));
  addTearDown(() async {
    await GetIt.I.unregister<Logger>();
  });
}
