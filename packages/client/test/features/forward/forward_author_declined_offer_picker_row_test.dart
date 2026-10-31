// The Forward picker row of a person whose offer the author declined says so
// ("Offer declined"), not "Withdrew commitment" — checked on a 375×667 phone
// in English and Russian, with the candidate built from a real
// `beaconInvolvement` response (Ferry link chain, only HTTP faked).
//
// The test font draws every glyph as a 13 px square, about twice as wide as
// the app font; what the test shows honestly is that the whole text is laid
// out on a 375 px row, nothing ellipsized.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/forward_wire_involvement.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

const _profile = Profile(
  id: 'Udeclined0001',
  displayName: 'Carol',
  rScore: 1,
  score: 40,
);

final _todayUtc = DateTime.utc(2026, 10, 31);

/// The row's candidate, as the picker would build it from the wire.
Future<ForwardCandidate> _candidateFromWire(
  WidgetTester tester, {
  List<String> withdrawnIds = const [],
}) async {
  final inv = (await tester.runAsync(
    () => fetchWireInvolvement(
      declinedOfferIds: [_profile.id],
      withdrawnIds: withdrawnIds,
    ),
  ))!;
  final involvement = ForwardCase.computeInvolvement(_profile.id, inv);
  expect(involvement, CandidateInvolvement.offerDeclinedByAuthor);
  return ForwardCandidate(profile: _profile, involvement: involvement);
}

Future<void> _pumpPhoneRow(
  WidgetTester tester, {
  required ForwardCandidate candidate,
  required Locale locale,
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  group('Forward picker row of a person whose offer the author declined', () {
    testWidgets('English: "Offer declined", not "Withdrew commitment"', (
      tester,
    ) async {
      final candidate = await _candidateFromWire(tester);
      await _pumpPhoneRow(
        tester,
        candidate: candidate,
        locale: const Locale('en'),
      );

      _expectWhole(tester, 'Offer declined');
      expect(find.text('Withdrew commitment'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'English: still "Offer declined" when also listed as withdrawn',
      (
        tester,
      ) async {
        final candidate = await _candidateFromWire(
          tester,
          withdrawnIds: [_profile.id],
        );
        await _pumpPhoneRow(
          tester,
          candidate: candidate,
          locale: const Locale('en'),
        );

        _expectWhole(tester, 'Offer declined');
        expect(find.text('Withdrew commitment'), findsNothing);
      },
    );

    testWidgets(
      'Russian: the translated copy is whole, not the withdrawal one',
      (
        tester,
      ) async {
        const locale = Locale('ru');
        final candidate = await _candidateFromWire(tester);
        final l10n = lookupL10n(locale);
        final copy = forwardRecipientRelationLabel(l10n, candidate);
        expect(copy, isNot(l10n.forwardWithdrawn));
        expect(copy, isNot('Offer declined'), reason: 'untranslated');

        await _pumpPhoneRow(tester, candidate: candidate, locale: locale);

        _expectWhole(tester, copy);
        expect(find.text(l10n.forwardWithdrawn), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
