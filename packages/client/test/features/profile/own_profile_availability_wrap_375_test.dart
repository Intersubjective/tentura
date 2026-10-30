// #267: On iPhone SE (375x667), own Profile availability line while paused
// ("Not taking new requests · until Nov 3, 2026" / "Вы не принимаете новые запросы · до 3 нояб. 2026 г.")
// wraps across two lines with no ellipsis and no clipping.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile/ui/widget/profile_body.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';

const _accountId = 'user-375';

final class _TestProfileCubit extends Cubit<ProfileState>
    implements ProfileCubit {
  _TestProfileCubit({required Profile profile})
    : super(ProfileState(profile: profile));

  @override
  bool get isAvailabilityResumeInFlight => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const iphoneSeSize = Size(375, 667);
  final fixedNow = DateTime.utc(2026, 8, 14, 12);
  DateTime clock() => fixedNow;
  final todayUtc = availabilityTodayUtc(clock);
  final resumeOn = DateTime.utc(2026, 11, 3);

  setUpAll(() async {
    await initializeDateFormatting();
  });

  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets(
      'Own profile availability line wraps to two lines on 375px width ($locale)',
      (tester) async {
        tester.view.physicalSize = iphoneSeSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final l10n = lookupL10n(locale);
        final expectedLine = ownAvailabilityPrimaryLine(
          l10n,
          Availability(resumeOn: resumeOn),
          todayUtc,
        );

        final pausedProfile = Profile(
          id: _accountId,
          displayName: 'Me',
          availability: Availability(resumeOn: resumeOn),
        );
        final profileCubit = _TestProfileCubit(profile: pausedProfile);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: iphoneSeSize,
              textScaler: TextScaler.noScaling,
            ),
            child: MaterialApp(
              locale: locale,
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileCubit>.value(value: profileCubit),
                  BlocProvider(create: (_) => ScreenCubit.local()),
                ],
                child: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      ProfileBody(
                        profile: pausedProfile,
                        profileCubit: profileCubit,
                        clock: clock,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final lineFinder = find.text(expectedLine);
        expect(lineFinder, findsOneWidget);

        final paragraph = tester.renderObject<RenderParagraph>(lineFinder);

        // Must not be truncated/ellipsized on line 1.
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'Line must not exceed max lines or show ellipsis',
        );

        // Must wrap across two lines on a 375 px screen (multi-line height > 24.0).
        expect(
          paragraph.size.height,
          greaterThan(24.0),
          reason: 'Availability line must wrap across two lines',
        );
      },
    );
  }
}
