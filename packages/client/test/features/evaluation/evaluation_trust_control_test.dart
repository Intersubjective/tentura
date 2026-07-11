import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_trust_selection.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_trust_control.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Widget _wrap({
  required Widget child,
  required Size size,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    theme: TenturaTheme.light(),
    home: BlocProvider<ProfileCubit>.value(
      value: _MockProfileCubit(),
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('step 1 to step 2 shows preview for completed selection', (
    tester,
  ) async {
    EvaluationTrustSelection? last;

    await tester.pumpWidget(
      _wrap(
        size: const Size(400, 900),
        child: EvaluationTrustControl(
          selection: EvaluationTrustSelection.unselected,
          onChanged: (s) => last = s,
          participantName: 'Alice',
        ),
      ),
    );

    await tester.tap(
      find.text('My trust in this person increased'),
    );
    await tester.pumpAndSettle();
    expect(last, EvaluationTrustSelection.increasePending);

    await tester.pumpWidget(
      _wrap(
        size: const Size(400, 900),
        child: EvaluationTrustControl(
          selection: EvaluationTrustSelection.increasePending,
          onChanged: (s) => last = s,
          participantName: 'Alice',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How much?'), findsOneWidget);
    await tester.tap(find.text('A little'));
    await tester.pumpAndSettle();
    expect(last, EvaluationTrustSelection.pos1);

    await tester.pumpWidget(
      _wrap(
        size: const Size(400, 900),
        child: EvaluationTrustControl(
          selection: EvaluationTrustSelection.pos1,
          onChanged: (_) {},
          participantName: 'Alice',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('your personal trust in Alice will increase slightly'),
      findsOneWidget,
    );
  });

  testWidgets('narrow width uses intensity column layout', (tester) async {
    await tester.pumpWidget(
      _wrap(
        size: const Size(375, 900),
        child: SizedBox(
          width: 343,
          child: EvaluationTrustControl(
            selection: EvaluationTrustSelection.decreasePending,
            onChanged: (_) {},
            participantName: 'Alice',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How much?'), findsOneWidget);
    expect(
      find.byKey(EvaluationTrustControl.intensityColumnKey),
      findsOneWidget,
    );
    expect(find.byKey(EvaluationTrustControl.intensityRowKey), findsNothing);
  });

  testWidgets('wide width uses intensity row layout', (tester) async {
    await tester.pumpWidget(
      _wrap(
        size: const Size(560, 900),
        child: SizedBox(
          width: 520,
          child: EvaluationTrustControl(
            selection: EvaluationTrustSelection.increasePending,
            onChanged: (_) {},
            participantName: 'Alice',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(EvaluationTrustControl.intensityRowKey), findsOneWidget);
    expect(find.byKey(EvaluationTrustControl.intensityColumnKey), findsNothing);
  });

  testWidgets('text scale 1.3 does not overflow on narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        size: const Size(375, 900),
        textScale: 1.3,
        child: EvaluationTrustControl(
          selection: EvaluationTrustSelection.decreasePending,
          onChanged: (_) {},
          participantName: 'Alice',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('russian locale renders contribution-framed labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        size: const Size(400, 900),
        locale: const Locale('ru'),
        child: EvaluationTrustControl(
          selection: EvaluationTrustSelection.unselected,
          onChanged: (_) {},
          participantName: 'Алиса',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('личное доверие'),
      findsOneWidget,
    );
    expect(
      find.text('Моё доверие к этому человеку увеличилось'),
      findsOneWidget,
    );
  });
}
