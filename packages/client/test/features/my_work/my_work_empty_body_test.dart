import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_empty_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('active empty shows onboarding CTAs', (tester) async {
    var createTapped = false;
    var inboxTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MyWorkEmptyBody(
            filter: MyWorkFilter.active,
            draftCount: 0,
            archivedCountHint: 0,
            onCreateBeacon: () => createTapped = true,
            onOpenInbox: () => inboxTapped = true,
            onShowDrafts: () {},
            onShowArchived: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create beacon'), findsOneWidget);
    expect(find.text('Go to Inbox'), findsOneWidget);

    await tester.tap(find.text('Create beacon'));
    await tester.tap(find.text('Go to Inbox'));
    expect(createTapped, isTrue);
    expect(inboxTapped, isTrue);
  });

  testWidgets('shortcuts shown when counts positive', (tester) async {
    var draftsTapped = false;
    var archiveTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: MyWorkEmptyBody(
            filter: MyWorkFilter.all,
            draftCount: 2,
            archivedCountHint: 3,
            onCreateBeacon: () {},
            onOpenInbox: () {},
            onShowDrafts: () => draftsTapped = true,
            onShowArchived: () => archiveTapped = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Drafts (2)'), findsOneWidget);
    expect(find.text('Archived (3)'), findsOneWidget);

    await tester.tap(find.text('Drafts (2)'));
    await tester.tap(find.text('Archived (3)'));
    expect(draftsTapped, isTrue);
    expect(archiveTapped, isTrue);
  });
}
