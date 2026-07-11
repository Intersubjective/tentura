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

Future<void> evaluationSelectNoChange(WidgetTester tester) async {
  await evaluationScrollAndTap(
    tester,
    find.text('This contribution did not change my trust'),
  );
}

Future<void> pumpEvaluationDetailSheet({
  required WidgetTester tester,
  required EvaluationParticipant participant,
  required Future<bool> Function(
    EvaluationValue,
    List<String>,
    String,
    List<String>,
  )
  onSave,
  Size size = const Size(400, 900),
  Locale locale = const Locale('en'),
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
          data: MediaQueryData(size: size),
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('open_sheet'),
                onPressed: () => showEvaluationDetailSheet(
                  context: context,
                  participant: participant,
                  onSave: onSave,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('open_sheet')));
  await tester.pumpAndSettle();
}
