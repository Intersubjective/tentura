// #463: the stop-trusting confirmation still said "delete … from friends
// list" after #84 moved the app to one-way trust wording.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/friends/ui/dialog/friend_remove_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  for (final (locale, title, confirm) in [
    ('en', 'Stop trusting Vadim?', 'Stop trusting'),
    ('ru', 'Перестать доверять пользователю Vadim?', 'Перестать доверять'),
  ]) {
    testWidgets('asks to stop trusting ($locale)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale(locale),
          home: Scaffold(
            body: FriendRemoveDialog(
              profile: const Profile(id: 'U1', displayName: 'Vadim'),
              onRemove: () async {},
            ),
          ),
        ),
      );

      expect(find.text(title), findsOneWidget);
      expect(find.widgetWithText(TextButton, confirm), findsOneWidget);
    });
  }
}
