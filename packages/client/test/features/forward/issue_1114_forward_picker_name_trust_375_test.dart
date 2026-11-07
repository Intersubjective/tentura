// #1114: on iPhone SE width, direct forward rows keep the contact name and
// «You trust them» readable (no crushed one-line ellipsis).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
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

Future<void> _pumpRow(
  WidgetTester tester, {
  required Locale locale,
  required ForwardCandidate candidate,
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
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectSubstringVisible(WidgetTester tester, String fragment) {
  final finder = find.textContaining(fragment);
  expect(finder, findsWidgets);
  final paragraph = tester.renderObject<RenderParagraph>(finder.first);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'truncated: $fragment',
  );
  expect(paragraph.text.toPlainText(), contains(fragment));
}

void main() {
  const name = 'QA779 Ann Mutual';
  final candidate = ForwardCandidate(
    profile: Profile(
      id: 'ann',
      displayName: name,
      rScore: 1,
      score: 80,
      myVote: 1,
    ),
    involvement: CandidateInvolvement.unseen,
    reach: const ForwardReach(kind: ForwardReachKind.direct),
  );

  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets(
      '#1114 ${locale.languageCode} 375×667: name and trust line stay readable',
      (tester) async {
        final l10n = lookupL10n(locale);
        await _pumpRow(tester, locale: locale, candidate: candidate);

        _expectSubstringVisible(tester, 'QA779');
        _expectSubstringVisible(tester, l10n.forwardReachYouTrustThem);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
