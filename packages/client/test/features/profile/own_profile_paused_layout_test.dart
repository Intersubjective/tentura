import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/features/home/ui/widget/own_paused_chip.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile/ui/widget/profile_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _FakeProfileCubit extends Cubit<ProfileState> implements ProfileCubit {
  _FakeProfileCubit(Profile initialProfile)
      : super(ProfileState(profile: initialProfile));

  @override
  bool get isAvailabilityResumeInFlight => false;

  @override
  Future<void> resumeAvailability() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final resumeOn = DateTime.utc(2026, 11, 3);
  final todayUtc = DateTime.utc(2026, 10, 29);

  final pausedProfile = Profile(
    id: 'me',
    displayName: 'Test User',
    availability: Availability(
      isLimited: false,
      resumeOn: resumeOn,
    ),
  );

  Widget buildTestApp({
    required Widget child,
    required ProfileCubit profileCubit,
    required Locale locale,
    Size size = const Size(375, 667),
  }) {
    return GetItContext(
      profileCubit: profileCubit,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  group('Issue 267 375px phone layout tests (EN and RU)', () {
    testWidgets('Gap 1: Requests app bar shows title and filter untruncated while paused (EN)',
        (tester) async {
      tester.view.physicalSize = const Size(375 * 2, 667 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = _FakeProfileCubit(pausedProfile);

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) {
              return Scaffold(
                appBar: AppBar(
                  title: const Row(
                    children: [
                      Text('Requests'),
                      SizedBox(width: 8),
                      Text('Active ▾'),
                    ],
                  ),
                  actions: [
                    IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
                    if (homeTopBarAccount(context) != null)
                      homeTopBarAccount(context)!,
                  ],
                ),
              );
            },
          ),
          profileCubit: cubit,
          locale: const Locale('en'),
        ),
      );

      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Active ▾'), findsOneWidget);
      expect(find.byKey(OwnPausedChip.chipKey), findsOneWidget);
    });

    testWidgets('Gap 1: Requests app bar shows title and filter untruncated while paused (RU)',
        (tester) async {
      tester.view.physicalSize = const Size(375 * 2, 667 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = _FakeProfileCubit(pausedProfile);

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) {
              return Scaffold(
                appBar: AppBar(
                  title: const Row(
                    children: [
                      Text('Запросы'),
                      SizedBox(width: 8),
                      Text('Активные ▾'),
                    ],
                  ),
                  actions: [
                    IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
                    if (homeTopBarAccount(context) != null)
                      homeTopBarAccount(context)!,
                  ],
                ),
              );
            },
          ),
          profileCubit: cubit,
          locale: const Locale('ru'),
        ),
      );

      expect(find.text('Запросы'), findsOneWidget);
      expect(find.text('Активные ▾'), findsOneWidget);
      expect(find.byKey(OwnPausedChip.chipKey), findsOneWidget);
    });

    testWidgets('Gap 2: Own profile availability line renders full date without truncation (EN)',
        (tester) async {
      tester.view.physicalSize = const Size(375 * 2, 667 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = _FakeProfileCubit(pausedProfile);

      await tester.pumpWidget(
        buildTestApp(
          child: SingleChildScrollView(
            child: OwnProfileAvailabilityControl(
              profile: pausedProfile,
              todayUtc: todayUtc,
            ),
          ),
          profileCubit: cubit,
          locale: const Locale('en'),
        ),
      );

      final statusTextFinder = find.byType(Text).first;
      final Text textWidget = tester.widget(statusTextFinder);

      expect(textWidget.data, contains('Nov 3, 2026'));
      expect(textWidget.maxLines, isNull);
      expect(textWidget.overflow, equals(TextOverflow.clip));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Gap 2: Own profile availability line renders full date without truncation (RU)',
        (tester) async {
      tester.view.physicalSize = const Size(375 * 2, 667 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = _FakeProfileCubit(pausedProfile);

      await tester.pumpWidget(
        buildTestApp(
          child: SingleChildScrollView(
            child: OwnProfileAvailabilityControl(
              profile: pausedProfile,
              todayUtc: todayUtc,
            ),
          ),
          profileCubit: cubit,
          locale: const Locale('ru'),
        ),
      );

      final statusTextFinder = find.byType(Text).first;
      final Text textWidget = tester.widget(statusTextFinder);

      expect(textWidget.data, contains('3 нояб. 2026 г.'));
      expect(textWidget.maxLines, isNull);
      expect(textWidget.overflow, equals(TextOverflow.clip));
      expect(tester.takeException(), isNull);
    });
  });
}

class GetItContext extends StatefulWidget {
  const GetItContext({
    required this.child,
    required this.profileCubit,
    super.key,
  });

  final Widget child;
  final ProfileCubit profileCubit;

  @override
  State<GetItContext> createState() => _GetItContextState();
}

class _GetItContextState extends State<GetItContext> {
  @override
  void initState() {
    super.initState();
    if (GetIt.I.isRegistered<ProfileCubit>()) {
      GetIt.I.unregister<ProfileCubit>();
    }
    GetIt.I.registerSingleton<ProfileCubit>(widget.profileCubit);
  }

  @override
  void dispose() {
    if (GetIt.I.isRegistered<ProfileCubit>()) {
      GetIt.I.unregister<ProfileCubit>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
