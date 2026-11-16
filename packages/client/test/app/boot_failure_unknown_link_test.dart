import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/boot_failure_app.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> dispatch(
    WidgetTester tester,
    String method,
    Object? arguments,
  ) async {
    final data = const JSONMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      data,
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const BootFailureApp(isWeb: true));
    await tester.pumpAndSettle();
  }

  void expectStillBootFailure(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    final l10n = L10n.of(tester.element(find.byType(Scaffold)))!;
    expect(find.text(l10n.bootFailureTitle), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    // No other route was pushed: the boot-failure screen is still the only
    // route on the navigator stack.
    final route = ModalRoute.of(tester.element(find.byType(Scaffold)))!;
    expect(route.isFirst, isTrue);
    expect(route.isCurrent, isTrue);
    expect(route.settings.name, '/');
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
  }

  testWidgets('unknown route information keeps the boot-failure screen', (
    tester,
  ) async {
    await pumpApp(tester);
    await dispatch(tester, 'pushRouteInformation', <String, dynamic>{
      'location': '/doesnotexist',
      'state': null,
    });
    expectStillBootFailure(tester);
  });

  testWidgets('legacy pushRoute keeps the boot-failure screen', (tester) async {
    await pumpApp(tester);
    await dispatch(tester, 'pushRoute', '/doesnotexist');
    expectStillBootFailure(tester);
  });
}
