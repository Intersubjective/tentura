// #792: on a 375 px phone, a forwarded recipient row with Edit/Cancel actions
// must show the full "Forwarded by you" status and keep the read receipt on
// the same status line (not pushed to a third line).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
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

const _phone = Size(375, 667);

const _forwarded = ForwardCandidate(
  profile: Profile(id: 'bob', displayName: 'Bob', rScore: 1, score: 40),
  involvement: CandidateInvolvement.forwardedByMe,
);

Future<void> _pumpRow(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  tester.view
    ..physicalSize = _phone
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
            candidate: _forwarded,
            isSelected: false,
            onToggle: () {},
            onEditForward: () {},
            onCancelForward: () {},
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

int _lineCount(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
  )..layout(maxWidth: paragraph.size.width);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

void main() {
  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets(
      '#792 forwarded row at 375 px (${locale.languageCode}): status in full',
      (tester) async {
        final l10n = lookupL10n(locale);
        final status = l10n.forwardedByMe;

        await _pumpRow(tester, locale: locale);

        _expectWhole(tester, status);

        final statusParagraph = tester.renderObject<RenderParagraph>(
          find.text(status),
        );
        expect(
          _lineCount(statusParagraph),
          lessThanOrEqualTo(2),
          reason: 'status may wrap once; must not fragment mid-word',
        );

        expect(tester.takeException(), isNull);
      },
    );
  }
}
