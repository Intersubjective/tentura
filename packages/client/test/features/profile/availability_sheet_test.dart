import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile/ui/sheet/availability_sheet.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 8, 14, 15, 30);
  DateTime clock() => fixedNow;
  final todayUtc = availabilityTodayUtc(clock);

  group('AvailabilitySheetBody', () {
    testWidgets('open profile shows limited switch off and no resume action',
        (tester) async {
      final cubit = _TestProfileCubit(
        profile: const Profile(id: 'U-me', displayName: 'Me'),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);
      final l10n = lookupL10n(const Locale('en'));

      expect(
        tester.widget<SwitchListTile>(
          find.byKey(const Key('availability_limited_switch')),
        ).value,
        isFalse,
      );
      expect(find.text(l10n.availabilityResumeNow), findsNothing);
      expect(find.byKey(const Key('availability_pause_button')), findsOneWidget);
    });

    testWidgets('limited profile reflects cubit-confirmed switch value',
        (tester) async {
      final cubit = _TestProfileCubit(
        profile: Profile(
          id: 'U-me',
          displayName: 'Me',
          availability: const Availability(isLimited: true),
        ),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      expect(
        tester.widget<SwitchListTile>(
          find.byKey(const Key('availability_limited_switch')),
        ).value,
        isTrue,
      );
    });

    testWidgets('paused profile shows resume now action', (tester) async {
      final cubit = _TestProfileCubit(
        profile: Profile(
          id: 'U-me',
          displayName: 'Me',
          availability: Availability(resumeOn: DateTime.utc(2026, 8, 20)),
        ),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);
      final l10n = lookupL10n(const Locale('en'));

      expect(find.text(l10n.availabilityResumeNow), findsOneWidget);
    });

    testWidgets('limited+paused keeps limited switch on with resume action',
        (tester) async {
      final cubit = _TestProfileCubit(
        profile: Profile(
          id: 'U-me',
          displayName: 'Me',
          availability: Availability(
            isLimited: true,
            resumeOn: DateTime.utc(2026, 8, 20),
          ),
        ),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      expect(
        tester.widget<SwitchListTile>(
          find.byKey(const Key('availability_limited_switch')),
        ).value,
        isTrue,
      );
      expect(find.byKey(const Key('availability_resume_now')), findsOneWidget);
    });

    testWidgets('limited toggle stays open and reflects confirmed cubit state',
        (tester) async {
      final cubit = _TestProfileCubit(
        profile: const Profile(id: 'U-me', displayName: 'Me'),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      await tester.tap(find.byKey(const Key('availability_limited_switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(cubit.setLimitedCalls, 1);
      expect(cubit.lastSetLimitedValue, isTrue);
      expect(find.byType(AvailabilitySheetBody), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(
          find.byKey(const Key('availability_limited_switch')),
        ).value,
        isTrue,
      );
    });

    testWidgets('pause in flight disables only pause controls', (tester) async {
      final cubit = _TestProfileCubit(
        profile: const Profile(id: 'U-me', displayName: 'Me'),
      )..pauseInFlight = true;
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      expect(
        tester.widget<SwitchListTile>(
          find.byKey(const Key('availability_limited_switch')),
        ).onChanged,
        isNotNull,
      );
      expect(
        tester.widget<FilledButton>(
          find.byKey(const Key('availability_pause_button')),
        ).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(
          find.descendant(
            of: find.byKey(const Key('availability_preset_tomorrow')),
            matching: find.byType(OutlinedButton),
          ),
        ).onPressed,
        isNull,
      );
    });

    testWidgets('limited in flight disables only limited switch', (tester) async {
      final cubit = _TestProfileCubit(
        profile: const Profile(id: 'U-me', displayName: 'Me'),
      )..limitedInFlight = true;
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      expect(
        tester.widget<SwitchListTile>(
          find.byKey(const Key('availability_limited_switch')),
        ).onChanged,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(
          find.descendant(
            of: find.byKey(const Key('availability_preset_tomorrow')),
            matching: find.byType(OutlinedButton),
          ),
        ).onPressed,
        isNotNull,
      );
    });

    testWidgets('resume in flight disables only resume action', (tester) async {
      final cubit = _TestProfileCubit(
        profile: Profile(
          id: 'U-me',
          displayName: 'Me',
          availability: Availability(resumeOn: DateTime.utc(2026, 8, 20)),
        ),
      )..resumeInFlight = true;
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      expect(
        tester.widget<SwitchListTile>(
          find.byKey(const Key('availability_limited_switch')),
        ).onChanged,
        isNotNull,
      );
      expect(
        tester.widget<TextButton>(
          find.descendant(
            of: find.byKey(const Key('availability_resume_now')),
            matching: find.byType(TextButton),
          ),
        ).onPressed,
        isNull,
      );
    });

    group('dynamic in-flight via completer-backed commands', () {
      testWidgets('limited command disables only limited switch until complete',
          (tester) async {
        final limitedCompleter = Completer<void>();
        final cubit = _TestProfileCubit(
          profile: const Profile(id: 'U-me', displayName: 'Me'),
        )..limitedCommandCompleter = limitedCompleter;
        addTearDown(cubit.close);

        await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

        await tester.tap(find.byKey(const Key('availability_limited_switch')));
        await tester.pump();

        expect(
          tester.widget<SwitchListTile>(
            find.byKey(const Key('availability_limited_switch')),
          ).onChanged,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(
            find.descendant(
              of: find.byKey(const Key('availability_preset_tomorrow')),
              matching: find.byType(OutlinedButton),
            ),
          ).onPressed,
          isNotNull,
        );
        expect(cubit.setLimitedCalls, 1);

        limitedCompleter.complete();
        await tester.pumpAndSettle();

        expect(
          tester.widget<SwitchListTile>(
            find.byKey(const Key('availability_limited_switch')),
          ).onChanged,
          isNotNull,
        );
        expect(
          tester.widget<SwitchListTile>(
            find.byKey(const Key('availability_limited_switch')),
          ).value,
          isTrue,
        );
      });

      testWidgets('pause command disables only pause controls until complete',
          (tester) async {
        final pauseCompleter = Completer<void>();
        final cubit = _TestProfileCubit(
          profile: const Profile(id: 'U-me', displayName: 'Me'),
        )..pauseCommandCompleter = pauseCompleter;
        addTearDown(cubit.close);

        await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

        await tester.tap(find.byKey(const Key('availability_preset_tomorrow')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('availability_pause_button')));
        await tester.pump();

        expect(
          tester.widget<SwitchListTile>(
            find.byKey(const Key('availability_limited_switch')),
          ).onChanged,
          isNotNull,
        );
        expect(
          tester.widget<FilledButton>(
            find.byKey(const Key('availability_pause_button')),
          ).onPressed,
          isNull,
        );
        expect(
          tester.widget<OutlinedButton>(
            find.descendant(
              of: find.byKey(const Key('availability_preset_tomorrow')),
              matching: find.byType(OutlinedButton),
            ),
          ).onPressed,
          isNull,
        );
        expect(cubit.pauseCalls, 1);

        pauseCompleter.complete();
        await tester.pumpAndSettle();

        expect(find.byType(AvailabilitySheetBody), findsNothing);
        expect(find.text('Open sheet'), findsOneWidget);
      });

      testWidgets('resume command disables only resume action until complete',
          (tester) async {
        final resumeCompleter = Completer<void>();
        final cubit = _TestProfileCubit(
          profile: Profile(
            id: 'U-me',
            displayName: 'Me',
            availability: Availability(resumeOn: DateTime.utc(2026, 8, 20)),
          ),
        )..resumeCommandCompleter = resumeCompleter;
        addTearDown(cubit.close);

        await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

        await tester.tap(find.byKey(const Key('availability_resume_now')));
        await tester.pump();

        expect(
          tester.widget<SwitchListTile>(
            find.byKey(const Key('availability_limited_switch')),
          ).onChanged,
          isNotNull,
        );
        expect(
          tester.widget<TextButton>(
            find.descendant(
              of: find.byKey(const Key('availability_resume_now')),
              matching: find.byType(TextButton),
            ),
          ).onPressed,
          isNull,
        );
        expect(cubit.resumeCalls, 1);

        resumeCompleter.complete();
        await tester.pumpAndSettle();

        expect(find.byType(AvailabilitySheetBody), findsNothing);
        expect(find.text('Open sheet'), findsOneWidget);
      });

      testWidgets('failed pause command re-enables pause controls and keeps sheet',
          (tester) async {
        final pauseCompleter = Completer<void>();
        final cubit = _TestProfileCubit(
          profile: const Profile(id: 'U-me', displayName: 'Me'),
        )
          ..pauseCommandCompleter = pauseCompleter
          ..pauseError = Exception('offline');
        addTearDown(cubit.close);

        await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

        await tester.tap(find.byKey(const Key('availability_preset_tomorrow')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('availability_pause_button')));
        await tester.pump();

        expect(
          tester.widget<FilledButton>(
            find.byKey(const Key('availability_pause_button')),
          ).onPressed,
          isNull,
        );

        pauseCompleter.complete();
        await tester.pumpAndSettle();

        expect(find.byType(AvailabilitySheetBody), findsOneWidget);
        expect(cubit.effects.emitted.whereType<ShowError>(), hasLength(1));
        expect(
          tester.widget<FilledButton>(
            find.byKey(const Key('availability_pause_button')),
          ).onPressed,
          isNotNull,
        );
        expect(
          tester.widget<SwitchListTile>(
            find.byKey(const Key('availability_limited_switch')),
          ).onChanged,
          isNotNull,
        );
      });
    });

    testWidgets('pause failure retains sheet and emits one ShowError',
        (tester) async {
      final cubit = _TestProfileCubit(
        profile: const Profile(id: 'U-me', displayName: 'Me'),
      )..pauseError = Exception('offline');
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      await tester.tap(find.byKey(const Key('availability_preset_tomorrow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('availability_pause_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AvailabilitySheetBody), findsOneWidget);
      expect(cubit.effects.emitted.whereType<ShowError>(), hasLength(1));
      expect(cubit.pauseCalls, 1);
    });

    testWidgets('confirmed pause closes the sheet', (tester) async {
      final resumeOn = availabilityTomorrowPreset(todayUtc);
      final cubit = _TestProfileCubit(
        profile: const Profile(id: 'U-me', displayName: 'Me'),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      await tester.tap(find.byKey(const Key('availability_preset_tomorrow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('availability_pause_button')));
      await tester.pumpAndSettle();

      expect(find.byType(AvailabilitySheetBody), findsNothing);
      expect(find.text('Open sheet'), findsOneWidget);
      expect(cubit.pauseCalls, 1);
      expect(cubit.lastPauseResumeOn, resumeOn);
    });

    testWidgets('confirmed resume closes the sheet', (tester) async {
      final cubit = _TestProfileCubit(
        profile: Profile(
          id: 'U-me',
          displayName: 'Me',
          availability: Availability(resumeOn: DateTime.utc(2026, 8, 20)),
        ),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      await tester.tap(find.byKey(const Key('availability_resume_now')));
      await tester.pumpAndSettle();

      expect(find.byType(AvailabilitySheetBody), findsNothing);
      expect(find.text('Open sheet'), findsOneWidget);
      expect(cubit.resumeCalls, 1);
    });

    testWidgets('date picker bounds use tomorrow through today+90', (tester) async {
      final cubit = _TestProfileCubit(
        profile: const Profile(id: 'U-me', displayName: 'Me'),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);

      final tomorrow = availabilityPickerLocalDate(
        availabilityTomorrowPreset(todayUtc),
      );
      final maxDate = availabilityPickerLocalDate(
        availabilityMaxResumeOn(todayUtc),
      );

      await tester.tap(find.byKey(const Key('availability_preset_pick_date')));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(dialog.firstDate, tomorrow);
      expect(dialog.lastDate, maxDate);
      expect(dialog.initialDate, tomorrow);
    });

    testWidgets('picked local date converts to UTC calendar echo before pause',
        (tester) async {
      final cubit = _TestProfileCubit(
        profile: const Profile(id: 'U-me', displayName: 'Me'),
      );
      addTearDown(cubit.close);

      await pumpAvailabilitySheet(tester, cubit: cubit, clock: clock);
      final l10n = lookupL10n(const Locale('en'));

      final resumeOn = availabilityOneWeekPreset(todayUtc);
      await tester.tap(find.byKey(const Key('availability_preset_one_week')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          l10n.availabilityResumeEcho(
            availabilityWhenLabel(l10n, resumeOn, todayUtc),
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(
          find.byKey(const Key('availability_pause_button')),
        ).onPressed,
        isNotNull,
      );
    });
  });
}

Future<void> pumpAvailabilitySheet(
  WidgetTester tester, {
  required _TestProfileCubit cubit,
  required DateTime Function() clock,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: BlocProvider<ProfileCubit>.value(
          value: cubit,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: AvailabilitySheetBody(
                        profileCubit: cubit,
                        clock: clock,
                      ),
                    ),
                  ),
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open sheet'));
  await tester.pumpAndSettle();
}

final class _TestProfileCubit extends Cubit<ProfileState> implements ProfileCubit {
  _TestProfileCubit({required Profile profile})
    : effects = FakeUiEffectPort(),
      super(ProfileState(profile: profile));

  final FakeUiEffectPort effects;

  bool limitedInFlight = false;
  bool pauseInFlight = false;
  bool resumeInFlight = false;
  Object? pauseError;

  Completer<void>? limitedCommandCompleter;
  Completer<void>? pauseCommandCompleter;
  Completer<void>? resumeCommandCompleter;

  int setLimitedCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  bool? lastSetLimitedValue;
  DateTime? lastPauseResumeOn;

  @override
  bool get isAvailabilityLimitedInFlight => limitedInFlight;

  @override
  bool get isAvailabilityPauseInFlight => pauseInFlight;

  @override
  bool get isAvailabilityResumeInFlight => resumeInFlight;

  @override
  Future<void> setAvailabilityLimited(bool isLimited) async {
    setLimitedCalls++;
    lastSetLimitedValue = isLimited;
    limitedInFlight = true;
    final completer = limitedCommandCompleter;
    if (completer != null) {
      await completer.future;
    }
    limitedInFlight = false;
    emit(
      state.copyWith(
        profile: state.profile.copyWith(
          availability: state.profile.availability.copyWith(isLimited: isLimited),
        ),
      ),
    );
  }

  @override
  Future<void> pauseAvailability(DateTime resumeOn) async {
    pauseCalls++;
    lastPauseResumeOn = resumeOn;
    pauseInFlight = true;
    final completer = pauseCommandCompleter;
    if (completer != null) {
      await completer.future;
    }
    final failure = pauseError;
    pauseInFlight = false;
    if (failure != null) {
      effects.emit(ShowError(failure));
      return;
    }
    emit(
      state.copyWith(
        profile: state.profile.copyWith(
          availability: Availability(
            isLimited: state.profile.availability.isLimited,
            resumeOn: resumeOn,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> resumeAvailability() async {
    resumeCalls++;
    resumeInFlight = true;
    final completer = resumeCommandCompleter;
    if (completer != null) {
      await completer.future;
    }
    resumeInFlight = false;
    emit(
      state.copyWith(
        profile: state.profile.copyWith(
          availability: Availability.open(),
        ),
      ),
    );
  }

  @override
  Future<void> dispose() => close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
