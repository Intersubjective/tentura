// #730 / #267 on a 375 px phone (QA 7.56.5, iPhone SE): the Forward picker
// row cut its status to one ellipsized line, so the author's hint lost
// "People › Invite" (the only part that says what to do) and «Not taking new
// requests until …» lost the date. Both lines now wrap instead.
//
// The test font draws every glyph as a 13 px square, about twice as wide as
// the app font, so these strings need more test-font lines than the two they
// take on a phone. What the test can show honestly: the whole text is laid
// out on a 375 px row, with nothing ellipsized.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

final _todayUtc = DateTime.utc(2026, 10, 26);

const _dismissed = ForwardCandidate(
  profile: Profile(id: 'carol', displayName: 'Carol', rScore: 1, score: 40),
  involvement: CandidateInvolvement.declined,
);

final _paused = ForwardCandidate(
  profile: Profile(
    id: 'dave',
    displayName: 'Dave',
    rScore: 1,
    score: 30,
    availability: Availability(resumeOn: DateTime.utc(2026, 11, 18)),
  ),
);

Future<void> _pumpPhoneRow(
  WidgetTester tester, {
  required ForwardCandidate candidate,
  Locale locale = const Locale('en'),
  bool viewerIsAuthor = false,
}) async {
  tester.view
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(),
        child: Scaffold(
          body: ForwardRecipientRow(
            host: ForwardRecipientRowHost.pickerStandard,
            candidate: candidate,
            isSelected: false,
            onToggle: () {},
            onOpenDetails: () {},
            viewerIsAuthor: viewerIsAuthor,
            todayUtc: _todayUtc,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectWhole(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.text.toPlainText(), text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: 'cut: $text');
}

String _pausedLine(Locale locale) => computeForwardRecipientLine2(
  candidate: _paused,
  host: ForwardRecipientRowHost.pickerStandard,
  todayUtc: _todayUtc,
  l10n: lookupL10n(locale),
  locale: locale,
).presenceOrAvailabilityLine!;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  group('#730 the author hint on a 375 px row', () {
    testWidgets('English: "People › Invite" is not cut off', (tester) async {
      await _pumpPhoneRow(tester, candidate: _dismissed, viewerIsAuthor: true);
      _expectWhole(tester, 'They dismissed it — use People › Invite');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Russian: «Люди › Позвать» is not cut off', (tester) async {
      await _pumpPhoneRow(
        tester,
        candidate: _dismissed,
        locale: const Locale('ru'),
        viewerIsAuthor: true,
      );
      _expectWhole(tester, 'Убрал(а) запрос — позовите через «Люди › Позвать»');
      expect(tester.takeException(), isNull);
    });

    // Guard: a forwarder who is not the author keeps the plain words.
    testWidgets('a forwarder sees the plain words, whole', (tester) async {
      await _pumpPhoneRow(tester, candidate: _dismissed);
      _expectWhole(tester, 'Dismissed this request');
    });
  });

  group('#267 the availability line on a 375 px row', () {
    testWidgets('English: the date is shown', (tester) async {
      const locale = Locale('en');
      final line = _pausedLine(locale);
      expect(line, startsWith('Not taking new requests until '));
      await _pumpPhoneRow(tester, candidate: _paused);
      _expectWhole(tester, line);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Russian: the date is shown', (tester) async {
      const locale = Locale('ru');
      final line = _pausedLine(locale);
      expect(line, startsWith('Не принимает новые запросы до '));
      await _pumpPhoneRow(tester, candidate: _paused, locale: locale);
      _expectWhole(tester, line);
      expect(tester.takeException(), isNull);
    });
  });
}
