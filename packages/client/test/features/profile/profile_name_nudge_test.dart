import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/widget/profile_name_nudge.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('ProfileNameNudge shows for placeholder display name', (
    tester,
  ) async {
    const profile = Profile(
      id: 'U131e7da0f859',
      displayName: 'agent 3c4703tb',
    );

    await tester.pumpWidget(
      _wrap(
        BlocProvider(
          create: (_) => ScreenCubit.local(),
          child: const ProfileNameNudge(profile: profile),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add your display name'), findsOneWidget);
    expect(find.text('Set display name'), findsOneWidget);
  });

  testWidgets('ProfileNameNudge hidden for chosen display name', (
    tester,
  ) async {
    const profile = Profile(
      id: 'U131e7da0f859',
      displayName: 'Ada Lovelace',
    );

    await tester.pumpWidget(
      _wrap(const ProfileNameNudge(profile: profile)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add your display name'), findsNothing);
  });
}
