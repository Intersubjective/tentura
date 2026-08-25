import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_received.dart';
import 'package:tentura/features/evaluation/ui/bloc/received_reviews_cubit.dart';
import 'package:tentura/features/evaluation/ui/screen/received_reviews_screen.dart';
import 'package:tentura/features/evaluation/ui/widget/received_review_tile.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

EvaluationReceivedRow _row({
  required String name,
  required EvaluationReceivedTrustTone trustTone,
  int value = 4,
  String reviewerId = 'u1',
  List<String> acknowledgedHelpTags = const [],
  List<String> reasonTags = const [],
  String note = '',
}) => EvaluationReceivedRow(
  reviewerId: reviewerId,
  reviewerDisplayName: name,
  reviewerImageId: '',
  reviewerRole: 1,
  value: value,
  trustTone: trustTone,
  occurredAt: DateTime.utc(2026, 1, 1),
  reasonTags: reasonTags,
  acknowledgedHelpTags: acknowledgedHelpTags,
  note: note,
);

EvaluationReceived _payload({
  required bool windowClosed,
  List<EvaluationReceivedRow> rows = const [],
  String beaconTitle = 'Move help this weekend',
}) => EvaluationReceived(
  beaconId: 'b1',
  beaconTitle: beaconTitle,
  windowClosed: windowClosed,
  rows: rows,
);

class _FakeReceivedReviewsCubit extends ReceivedReviewsCubit {
  _FakeReceivedReviewsCubit(ReceivedReviewsState seed)
    : super(_MinimalRepo(), beaconId: 'b1') {
    emit(seed);
  }

  @override
  Future<void> fetch() async {}
}

class _MinimalRepo implements EvaluationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pumpView(
  WidgetTester tester, {
  required ReceivedReviewsState state,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: TenturaResponsiveScope(
        child: BlocProvider<ReceivedReviewsCubit>.value(
          value: _FakeReceivedReviewsCubit(state),
          child: const Scaffold(body: ReceivedReviewsView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpTile(
  WidgetTester tester, {
  required EvaluationReceivedRow row,
  double width = 800,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: ReceivedReviewTile(row: row, showDivider: false),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ReceivedReviewsScreen', () {
    testWidgets('renders received review rows when window is closed', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: ReceivedReviewsState(
          status: StateStatus.isSuccess,
          data: _payload(
            windowClosed: true,
            rows: [
              _row(
                name: 'Alex K.',
                trustTone: EvaluationReceivedTrustTone.up,
                value: 5,
              ),
              _row(
                name: 'Mira T.',
                trustTone: EvaluationReceivedTrustTone.noChange,
                reviewerId: 'u2',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Alex K.'), findsOneWidget);
      expect(find.text('Mira T.'), findsOneWidget);
      expect(find.text('Helped a lot'), findsOneWidget);
      expect(find.text('Helped somewhat'), findsOneWidget);
    });

    testWidgets('window open shows not-available-yet copy', (tester) async {
      await _pumpView(
        tester,
        state: ReceivedReviewsState(
          status: StateStatus.isSuccess,
          data: _payload(windowClosed: false),
        ),
      );

      expect(
        find.text('Reviews will appear here once the request finishes.'),
        findsOneWidget,
      );
      expect(find.text('See review window status'), findsOneWidget);
    });

    testWidgets('closed window with zero rows shows empty copy', (
      tester,
    ) async {
      await _pumpView(
        tester,
        state: ReceivedReviewsState(
          status: StateStatus.isSuccess,
          data: _payload(windowClosed: true),
        ),
      );

      expect(
        find.text('No one left feedback for you on this request.'),
        findsOneWidget,
      );
    });
  });

  group('ReceivedReviewTile trust tone', () {
    testWidgets('renders exact five impact values and no basis', (
      tester,
    ) async {
      await _pumpTile(
        tester,
        row: _row(
          name: 'Deni R.',
          trustTone: EvaluationReceivedTrustTone.noBasis,
          value: 0,
        ),
      );

      expect(find.text('No basis'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);

      await _pumpTile(
        tester,
        row: _row(
          name: 'Unknown wire value',
          trustTone: EvaluationReceivedTrustTone.noChange,
          value: 99,
        ),
      );
      expect(find.text('No basis'), findsOneWidget);
      expect(find.text('99'), findsNothing);

      for (final entry in <(int, String, IconData)>[
        (5, 'Helped a lot', Icons.keyboard_double_arrow_up_rounded),
        (4, 'Helped somewhat', Icons.arrow_upward_rounded),
        (3, 'No real effect', Icons.remove_rounded),
        (2, 'Hurt somewhat', Icons.arrow_downward_rounded),
        (1, 'Hurt a lot', Icons.keyboard_double_arrow_down_rounded),
      ]) {
        await _pumpTile(
          tester,
          row: _row(
            name: 'Mira T.',
            trustTone: EvaluationReceivedTrustTone.noChange,
            reviewerId: 'u${entry.$1}',
            value: entry.$1,
          ),
        );
        expect(find.text(entry.$2), findsOneWidget);
        expect(find.byIcon(entry.$3), findsOneWidget);
      }
    });

    testWidgets('renders reviewer details and localized legacy reasons', (
      tester,
    ) async {
      await _pumpTile(
        tester,
        row: _row(
          name: 'Alex Reviewer',
          trustTone: EvaluationReceivedTrustTone.up,
          value: 5,
          acknowledgedHelpTags: const ['transport', 'pets', 'storage'],
          reasonTags: const ['clear_request', 'future_unknown_reason'],
          note: 'Fast and careful.',
        ),
      );
      expect(find.text('Alex Reviewer'), findsOneWidget);
      expect(find.text('Transport, Storage +1'), findsOneWidget);
      expect(find.text('Fast and careful.'), findsOneWidget);
      expect(find.text('Clear request'), findsOneWidget);
      expect(find.text('Reason'), findsOneWidget);
      expect(find.text('clear_request'), findsNothing);
      expect(find.text('future_unknown_reason'), findsNothing);
    });

    testWidgets('wraps details at compact, expanded, and large text scales', (
      tester,
    ) async {
      for (final dimensions in <(double, double)>[
        (320, 1),
        (840, 1),
        (320, 2),
      ]) {
        await _pumpTile(
          tester,
          width: dimensions.$1,
          textScale: dimensions.$2,
          row: _row(
            name: 'Large text reviewer',
            trustTone: EvaluationReceivedTrustTone.up,
            value: 4,
            note: 'A note that should wrap without exposing wire values.',
          ),
        );
        expect(find.text('Helped somewhat'), findsOneWidget);
      }
    });
  });
}
