// #267: your own paused state is visible outside the profile. While you
// have paused new requests, a chip beside your avatar in the top bar reads
// "Paused until <date>" (RU «Пауза до <date>»); tapping it offers to resume.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/features/home/ui/widget/own_paused_chip.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 8, 14, 15, 30);
  DateTime clock() => fixedNow;
  final todayUtc = availabilityTodayUtc(clock);
  final resumeOn = DateTime.utc(2026, 8, 20);

  Profile pausedProfile() => Profile(
    id: 'U-me',
    displayName: 'Me',
    availability: Availability(resumeOn: resumeOn),
  );

  Future<_TestProfileCubit> pump(
    WidgetTester tester, {
    required Profile profile,
    Locale locale = const Locale('en'),
    bool iconOnly = false,
  }) async {
    final cubit = _TestProfileCubit(profile: profile);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          appBar: AppBar(
            actions: [
              OwnPausedChip(
                profileCubit: cubit,
                clock: clock,
                iconOnly: iconOnly,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('no chip while open to requests', (tester) async {
    await pump(
      tester,
      profile: const Profile(id: 'U-me', displayName: 'Me'),
    );
    expect(find.byKey(OwnPausedChip.chipKey), findsNothing);
  });

  testWidgets('no chip while only limited', (tester) async {
    await pump(
      tester,
      profile: const Profile(
        id: 'U-me',
        displayName: 'Me',
        availability: Availability(isLimited: true),
      ),
    );
    expect(find.byKey(OwnPausedChip.chipKey), findsNothing);
  });

  testWidgets('paused: the chip names the resume date in English', (
    tester,
  ) async {
    await pump(tester, profile: pausedProfile());
    final l10n = lookupL10n(const Locale('en'));
    final when = availabilityWhenLabel(l10n, resumeOn, todayUtc);
    expect(find.byKey(OwnPausedChip.chipKey), findsOneWidget);
    expect(find.text('Paused until $when'), findsOneWidget);
  });

  testWidgets('paused: the chip names the resume date in Russian', (
    tester,
  ) async {
    await pump(tester, profile: pausedProfile(), locale: const Locale('ru'));
    final l10n = lookupL10n(const Locale('ru'));
    final when = availabilityWhenLabel(l10n, resumeOn, todayUtc);
    expect(find.text('Пауза до $when'), findsOneWidget);
  });

  testWidgets('a pause that has ended shows no chip', (tester) async {
    await pump(
      tester,
      profile: Profile(
        id: 'U-me',
        displayName: 'Me',
        availability: Availability(resumeOn: DateTime.utc(2026, 8, 14)),
      ),
    );
    expect(find.byKey(OwnPausedChip.chipKey), findsNothing);
  });

  testWidgets('tap, then confirm: resumes and the chip goes', (tester) async {
    final cubit = await pump(tester, profile: pausedProfile());
    final l10n = lookupL10n(const Locale('en'));

    await tester.tap(find.byKey(OwnPausedChip.chipKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.availabilityResumeConfirmTitle), findsOneWidget);
    expect(cubit.resumeCalls, 0);

    await tester.tap(find.text(l10n.availabilityResumeNow));
    await tester.pumpAndSettle();

    expect(cubit.resumeCalls, 1);
    expect(find.byKey(OwnPausedChip.chipKey), findsNothing);
  });

  testWidgets('tap, then cancel: stays paused', (tester) async {
    final cubit = await pump(tester, profile: pausedProfile());
    final l10n = lookupL10n(const Locale('en'));

    await tester.tap(find.byKey(OwnPausedChip.chipKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.buttonCancel));
    await tester.pumpAndSettle();

    expect(cubit.resumeCalls, 0);
    expect(find.byKey(OwnPausedChip.chipKey), findsOneWidget);
  });

  testWidgets('icon-only form names the date in its tooltip and resumes', (
    tester,
  ) async {
    final cubit = await pump(tester, profile: pausedProfile(), iconOnly: true);
    final l10n = lookupL10n(const Locale('en'));
    final when = availabilityWhenLabel(l10n, resumeOn, todayUtc);
    expect(find.byTooltip('Paused until $when'), findsOneWidget);

    await tester.tap(find.byKey(OwnPausedChip.chipKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.availabilityResumeNow));
    await tester.pumpAndSettle();
    expect(cubit.resumeCalls, 1);
  });

  testWidgets('compact top bar: the paused chip sits beside the avatar', (
    tester,
  ) async {
    // homeTopBarAccount uses the real clock: pause until a week from now.
    final cubit = _TestProfileCubit(
      profile: Profile(
        id: 'U-me',
        displayName: 'Me',
        availability: Availability(
          resumeOn: addUtcCalendarDays(availabilityTodayUtc(), 7),
        ),
      ),
    );
    addTearDown(cubit.close);
    GetIt.I.registerSingleton<ProfileCubit>(cubit);
    addTearDown(GetIt.I.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 800)),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                actions: [?homeTopBarAccount(context)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(AppBar);
    final chip = find.descendant(
      of: bar,
      matching: find.byKey(OwnPausedChip.chipKey),
    );
    final avatar = find.descendant(
      of: bar,
      matching: find.byKey(HomeAccountAvatarButton.buttonKey),
    );
    expect(chip, findsOneWidget);
    expect(avatar, findsOneWidget);
    expect(
      tester.getRect(chip).right,
      lessThanOrEqualTo(tester.getRect(avatar).left),
    );
  });

  // #267 review: the chip sat in an unbounded row, so its ellipsis never
  // kicked in and a long Russian date crowded the screen title at 360dp.
  testWidgets('360dp, Russian, a long date: the chip is bounded', (
    tester,
  ) async {
    const size = Size(360, 740);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final l10n = lookupL10n(const Locale('ru'));
    final today = availabilityTodayUtc();
    // The longest date label in the coming year.
    var longest = addUtcCalendarDays(today, 7);
    for (var d = 8; d < 380; d++) {
      final day = addUtcCalendarDays(today, d);
      if (availabilityWhenLabel(l10n, day, today).length >
          availabilityWhenLabel(l10n, longest, today).length) {
        longest = day;
      }
    }
    final cubit = _TestProfileCubit(
      profile: Profile(
        id: 'U-me',
        displayName: 'Me',
        availability: Availability(resumeOn: longest),
      ),
    );
    addTearDown(cubit.close);
    GetIt.I.registerSingleton<ProfileCubit>(cubit);
    addTearDown(GetIt.I.reset);
    // Test glyphs are 1em squares, so a short title stands in for a real one.
    const title = 'Чаты';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            appBar: TenturaTopBar.of(
              context,
              title: const Text(title),
              account: homeTopBarAccount(context),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chip = find.byKey(OwnPausedChip.chipKey);
    expect(chip, findsOneWidget);
    final chipRect = tester.getRect(chip);
    expect(
      chipRect.width,
      lessThanOrEqualTo(size.width * kTopBarPausedChipWidthShare + 0.5),
    );
    // The title is laid out whole, left of the chip.
    final titleFinder = find.text(title);
    final titleParagraph = tester.renderObject<RenderParagraph>(titleFinder);
    expect(
      titleParagraph.size.width,
      greaterThanOrEqualTo(
        titleParagraph.getMaxIntrinsicWidth(double.infinity) - 0.5,
      ),
    );
    expect(tester.getRect(titleFinder).right, lessThanOrEqualTo(chipRect.left));
    expect(
      chipRect.right,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(HomeAccountAvatarButton.buttonKey)).left,
      ),
    );
    // Since the SE QA (#267) the top bar shows the short date, whole; the
    // full words are the chip's tooltip and screen-reader label.
    final label = l10n.availabilityPausedChip(
      availabilityWhenLabel(l10n, longest, today),
    );
    final short = find.descendant(
      of: chip,
      matching: find.text(availabilityWhenShortLabel(l10n, longest, today)),
    );
    expect(short, findsOneWidget);
    _expectWhole(tester, short);
    expect(find.byTooltip(label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // #267 QA on iPhone SE (375x667), 7.56.1: the chip read "Paused unt…" /
  // «Пауза до 2…», so the date never showed, and it pushed the screen title
  // out of the top bar.
  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets('iPhone SE top bar: the date shows and the title stays '
        '($locale)', (tester) async {
      const size = Size(375, 667);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final l10n = lookupL10n(locale);
      final today = availabilityTodayUtc();
      // A month away: a dated label, not a weekday.
      final until = addUtcCalendarDays(today, 30);
      final semantics = tester.ensureSemantics();
      final cubit = _TestProfileCubit(
        profile: Profile(
          id: 'U-me',
          displayName: 'Me',
          availability: Availability(resumeOn: until),
        ),
      );
      addTearDown(cubit.close);
      GetIt.I.registerSingleton<ProfileCubit>(cubit);
      addTearDown(GetIt.I.reset);
      // Test glyphs are 1em squares, so a short title stands in for
      // "Requests"; one action stands in for the screen's own icons.
      const title = 'Чаты';
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              appBar: TenturaTopBar.of(
                context,
                title: const Text(title),
                actions: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                  ),
                ],
                account: homeTopBarAccount(context),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chip = find.byKey(OwnPausedChip.chipKey);
      expect(chip, findsOneWidget);
      final chipRect = tester.getRect(chip);

      // The date is on screen, whole.
      final date = availabilityWhenShortLabel(l10n, until, today);
      expect(date, isNot(contains('…')));
      final dateText = find.descendant(of: chip, matching: find.text(date));
      expect(dateText, findsOneWidget);
      _expectWhole(tester, dateText);
      expect(
        tester.getRect(dateText).right,
        lessThanOrEqualTo(chipRect.right + 0.5),
      );

      // The full words are the tooltip and what a screen reader hears.
      final label = l10n.availabilityPausedChip(
        availabilityWhenLabel(l10n, until, today),
      );
      expect(find.byTooltip(label), findsOneWidget);
      expect(find.bySemanticsLabel(label), findsOneWidget);

      // The screen title keeps its room, left of the chip.
      final titleFinder = find.text(title);
      _expectWhole(tester, titleFinder);
      expect(
        tester.getRect(titleFinder).right,
        lessThanOrEqualTo(chipRect.left),
      );
      expect(
        chipRect.right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(HomeAccountAvatarButton.buttonKey)).left,
        ),
      );

      // Tapping it still offers to resume.
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.text(l10n.availabilityResumeConfirmTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

/// [text] is laid out on one line at its full width (not ellipsized).
void _expectWhole(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
    paragraph.size.width,
    greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5),
  );
}

final class _TestProfileCubit extends Cubit<ProfileState>
    implements ProfileCubit {
  _TestProfileCubit({required Profile profile})
    : super(ProfileState(profile: profile));

  int resumeCalls = 0;

  @override
  bool get isAvailabilityResumeInFlight => false;

  @override
  Future<void> resumeAvailability() async {
    resumeCalls++;
    emit(
      state.copyWith(
        profile: state.profile.copyWith(availability: Availability.open()),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
