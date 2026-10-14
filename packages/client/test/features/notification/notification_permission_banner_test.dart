// B065: on web the browser's notification prompt is never shown on load. A
// small in-app banner explains why and what to click, and asks only from its
// own button.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/notification/domain/entity/notification_permission_status.dart';
import 'package:tentura/features/notification/domain/entity/notification_permissions.dart';
import 'package:tentura/features/notification/domain/use_case/fcm_case.dart';
import 'package:tentura/features/notification/ui/bloc/fcm_cubit.dart';
import 'package:tentura/features/notification/ui/widget/notification_permission_banner.dart';
import 'package:tentura/features/notification/ui/widget/notification_permission_device_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../auth/auth_test_helpers.dart';
import 'fcm_case_test.dart';

class _Harness {
  _Harness(NotificationPermissionStatus status)
    : local = FakeFcmLocal()
        ..status = status
        ..token = 'tok',
      remote = FakeFcmRemote(),
      settings = FakeSettings(appId: 'app-1') {
    cubit = FcmCubit(
      FcmCase(local, remote, settings),
      buildTestAuthCase(_SignedInAuthLocal(), EmptyAuthRemote()),
    );
  }

  final FakeFcmLocal local;
  final FakeFcmRemote remote;
  final FakeSettings settings;
  late final FcmCubit cubit;
}

Future<_Harness> _pump(
  WidgetTester tester,
  NotificationPermissionStatus status, {
  Widget? child,
  Locale locale = const Locale('en'),
  bool settingsTile = false,
}) async {
  FcmCubit.debugAsksOnLoad = false;
  addTearDown(() => FcmCubit.debugAsksOnLoad = null);
  final h = _Harness(status);
  addTearDown(h.cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: settingsTile
              ? NotificationPermissionDeviceTile(cubit: h.cubit)
              : NotificationPermissionPromptFrame(
                  cubit: h.cubit,
                  child: child ?? const Text('home'),
                ),
        ),
      ),
    ),
  );
  await tester.pump();
  return h;
}

final _allow = find.text('Turn on');
final _notNow = find.text('Not now');
final _title = find.text('Turn on notifications?');

void main() {
  testWidgets('first start: banner explains why and what to click; '
      'no browser prompt yet', (tester) async {
    final h = await _pump(tester, NotificationPermissionStatus.notDetermined);

    expect(_title, findsOneWidget);
    expect(
      find.textContaining('choose “Allow” when your browser asks'),
      findsOneWidget,
    );
    expect(_allow, findsOneWidget);
    expect(_notNow, findsOneWidget);
    expect(find.text('home'), findsOneWidget);
    expect(h.local.requestPermissionCalls, 0);
  });

  testWidgets('"Turn on" asks the browser, registers, and the banner goes', (
    tester,
  ) async {
    final h = await _pump(tester, NotificationPermissionStatus.notDetermined);
    h.local.permissionAfterRequest = NotificationPermissionStatus.granted;

    await tester.tap(_allow);
    await tester.pump();

    expect(h.local.requestPermissionCalls, 1);
    expect(h.remote.registerCalls, 1);
    expect(_title, findsNothing);
  });

  testWidgets('blocking in the browser dialog also hides the banner', (
    tester,
  ) async {
    final h = await _pump(tester, NotificationPermissionStatus.notDetermined);
    h.local
      ..permissionAfterRequest = NotificationPermissionStatus.denied
      ..permissionResult = const NotificationPermissions();

    await tester.tap(_allow);
    await tester.pump();

    expect(h.remote.registerCalls, 0);
    expect(_title, findsNothing);
  });

  testWidgets('closing the system dialog without an answer keeps the banner', (
    tester,
  ) async {
    final h = await _pump(tester, NotificationPermissionStatus.notDetermined);
    h.local.permissionResult = const NotificationPermissions();

    await tester.tap(_allow);
    await tester.pump();

    expect(h.local.requestPermissionCalls, 1);
    expect(_title, findsOneWidget);
  });

  testWidgets('"Not now" hides it, remembers it, never asks the browser', (
    tester,
  ) async {
    final h = await _pump(tester, NotificationPermissionStatus.notDetermined);

    await tester.tap(_notNow);
    await tester.pump();

    expect(_title, findsNothing);
    expect(h.settings.notificationPromptDismissed, isTrue);
    expect(h.local.requestPermissionCalls, 0);
  });

  testWidgets('a remembered "Not now" keeps the banner hidden next time', (
    tester,
  ) async {
    FcmCubit.debugAsksOnLoad = false;
    addTearDown(() => FcmCubit.debugAsksOnLoad = null);
    final h = _Harness(NotificationPermissionStatus.notDetermined);
    h.settings.notificationPromptDismissed = true;
    addTearDown(h.cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: NotificationPermissionPromptFrame(
          cubit: h.cubit,
          child: const Text('home'),
        ),
      ),
    );
    await tester.pump();

    expect(_title, findsNothing);
  });

  for (final status in [
    NotificationPermissionStatus.granted,
    NotificationPermissionStatus.denied,
    NotificationPermissionStatus.unsupported,
  ]) {
    testWidgets('hidden when permission is ${status.name}', (tester) async {
      await _pump(tester, status);
      expect(_title, findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  }

  testWidgets('the home content keeps its state when the banner goes', (
    tester,
  ) async {
    await _pump(
      tester,
      NotificationPermissionStatus.notDetermined,
      child: const _Counter(),
    );
    await tester.tap(find.byType(_Counter));
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);

    await tester.tap(_notNow);
    await tester.pump();

    expect(_title, findsNothing);
    expect(find.text('count 1'), findsOneWidget);
  });

  testWidgets('Russian copy names the browser button «Разрешить»', (
    tester,
  ) async {
    await _pump(
      tester,
      NotificationPermissionStatus.notDetermined,
      locale: const Locale('ru'),
    );
    expect(find.text('Включить уведомления?'), findsOneWidget);
    expect(find.textContaining('выберите «Разрешить»'), findsOneWidget);
    expect(find.text('Не сейчас'), findsOneWidget);
  });

  group('Notification settings row', () {
    testWidgets('not asked yet (or banner closed): offers "Turn on"', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        NotificationPermissionStatus.notDetermined,
        settingsTile: true,
      );
      expect(find.text('Notifications on this device'), findsOneWidget);

      await tester.tap(_allow);
      await tester.pump();
      expect(h.local.requestPermissionCalls, 1);
    });

    testWidgets('blocked: points to the browser site settings', (
      tester,
    ) async {
      await _pump(
        tester,
        NotificationPermissionStatus.denied,
        settingsTile: true,
      );
      expect(find.textContaining('open the site settings'), findsOneWidget);
      expect(_allow, findsNothing);
    });

    testWidgets('granted: nothing to show', (tester) async {
      await _pump(
        tester,
        NotificationPermissionStatus.granted,
        settingsTile: true,
      );
      expect(find.text('Notifications on this device'), findsNothing);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _count++),
    child: Text('count $_count'),
  );
}

class _SignedInAuthLocal extends EmptyAuthLocal {
  static const _accountId = 'Utest0000001';

  @override
  Stream<String> currentAccountChanges() => Stream.value(_accountId);

  @override
  Future<String> getCurrentAccountId() async => _accountId;
}
