import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_participant.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_detail_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

class MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Future<void> evaluationScrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> evaluationSelectImpact(
  WidgetTester tester,
  String label,
) => evaluationScrollAndTap(tester, find.text(label));

Future<void> pumpEvaluationDetailSheet({
  required WidgetTester tester,
  required EvaluationParticipant participant,
  required Future<bool> Function(
    EvaluationValue,
    String,
    List<String>,
  )
  onSave,
  Size size = const Size(400, 900),
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: BlocProvider<ProfileCubit>.value(
        value: MockProfileCubit(),
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: textScaler,
            viewInsets: viewInsets,
          ),
          child: ElevatedButton(
            onPressed: () => showEvaluationDetailSheet(
              context: tester.element(find.byType(ElevatedButton)),
              participant: participant,
              onSave: onSave,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  final open = find.widgetWithText(ElevatedButton, 'Open');
  await tester.ensureVisible(open);
  await tester.pumpAndSettle();
  await tester.tap(open);
  await tester.pumpAndSettle();
}

Finder evaluationSaveButton() =>
    find.byKey(TestIds.key(TestIds.evaluationSave));
