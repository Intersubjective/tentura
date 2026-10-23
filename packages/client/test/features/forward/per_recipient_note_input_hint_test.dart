// #607 (#439): the per-person note field under a picked recipient used to
// read «Note for Clara». Without a caller override it now reads as an
// optional note that still names the person; callers can still override it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

const _clara = Profile(id: 'u1', displayName: 'Clara');

Future<String> _hint(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  String? hintText,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: BlocProvider<ProfileCubit>.value(
          value: _ProfileCubit(),
          child: PerRecipientNoteInput(
            profile: _clara,
            controller: TextEditingController(),
            onChanged: (_) {},
            onClose: null,
            hintText: hintText,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final field = tester.widget<TextField>(find.byType(TextField));
  return field.decoration?.hintText ?? '';
}

void main() {
  testWidgets('default hint invites an optional note for the person', (
    tester,
  ) async {
    expect(await _hint(tester), 'Add a note for Clara (optional)');
  });

  testWidgets('ru: default hint is the translated optional note', (
    tester,
  ) async {
    expect(
      await _hint(tester, locale: const Locale('ru')),
      'Добавьте заметку для Clara (необязательно)',
    );
  });

  testWidgets('a caller hint still overrides the default', (tester) async {
    expect(
      await _hint(tester, hintText: 'Custom hint'),
      'Custom hint',
    );
  });
}
