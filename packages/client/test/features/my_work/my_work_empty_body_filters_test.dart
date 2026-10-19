import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_empty_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Issue #430: the Authored / Help offered / Drafts / Archived empty states
// were a bare title. Each must explain what lands there (one sentence of
// its own) and offer a next step (Create request / Go to Field).

class _Taps {
  int create = 0;
  int inbox = 0;
  int field = 0;
  int drafts = 0;
  int archived = 0;
}

Future<L10n> _pump(
  WidgetTester tester,
  MyWorkFilter filter,
  _Taps taps, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: MyWorkEmptyBody(
          filter: filter,
          draftCount: 0,
          archivedCountHint: 0,
          onCreateBeacon: () => taps.create++,
          onOpenInbox: () => taps.inbox++,
          onOpenConstellation: () => taps.field++,
          onShowDrafts: () => taps.drafts++,
          onShowArchived: () => taps.archived++,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return L10n.of(tester.element(find.byType(MyWorkEmptyBody)))!;
}

String _title(L10n l10n, MyWorkFilter filter) => switch (filter) {
  MyWorkFilter.authored => l10n.myWorkEmptyAuthored,
  MyWorkFilter.helpOffered => l10n.myWorkEmptyHelpOffered,
  MyWorkFilter.drafts => l10n.myWorkEmptyDrafts,
  MyWorkFilter.archived => l10n.myWorkEmptyArchived,
  _ => throw ArgumentError(filter),
};

String _body(L10n l10n, MyWorkFilter filter) => switch (filter) {
  MyWorkFilter.authored => l10n.myWorkEmptyAuthoredBody,
  MyWorkFilter.helpOffered => l10n.myWorkEmptyHelpOfferedBody,
  MyWorkFilter.drafts => l10n.myWorkEmptyDraftsBody,
  MyWorkFilter.archived => l10n.myWorkEmptyArchivedBody,
  _ => throw ArgumentError(filter),
};

const _filters = [
  MyWorkFilter.authored,
  MyWorkFilter.helpOffered,
  MyWorkFilter.drafts,
  MyWorkFilter.archived,
];

void _expectExplained(L10n l10n, MyWorkFilter filter) {
  expect(find.text(_title(l10n, filter)), findsOneWidget);
  expect(find.text(_body(l10n, filter)), findsOneWidget);
  // Negative guard: the Active-only copy and Activity CTAs stay on Active;
  // reusing them here would not explain this filter.
  expect(find.text(l10n.myWorkEmptyActiveBody), findsNothing);
  expect(find.text(l10n.myWorkEmptyActiveInboxCta), findsNothing);
}

void main() {
  testWidgets('authored empty explains itself and offers Create request', (
    tester,
  ) async {
    final taps = _Taps();
    final l10n = await _pump(tester, MyWorkFilter.authored, taps);

    _expectExplained(l10n, MyWorkFilter.authored);
    expect(find.text(l10n.myWorkEmptyActiveCreateCta), findsOneWidget);

    await tester.tap(find.text(l10n.myWorkEmptyActiveCreateCta));
    expect(taps.create, 1);
    expect(taps.inbox, 0);
  });

  testWidgets('drafts empty explains itself and offers Create request', (
    tester,
  ) async {
    final taps = _Taps();
    final l10n = await _pump(tester, MyWorkFilter.drafts, taps);

    _expectExplained(l10n, MyWorkFilter.drafts);
    expect(find.text(l10n.myWorkEmptyActiveCreateCta), findsOneWidget);

    await tester.tap(find.text(l10n.myWorkEmptyActiveCreateCta));
    expect(taps.create, 1);
    expect(taps.inbox, 0);
  });

  testWidgets('help offered empty explains itself and offers Go to Field', (
    tester,
  ) async {
    final taps = _Taps();
    final l10n = await _pump(tester, MyWorkFilter.helpOffered, taps);

    _expectExplained(l10n, MyWorkFilter.helpOffered);
    expect(l10n.myWorkEmptyGoToFieldCta, 'Go to Field');
    expect(find.text(l10n.myWorkEmptyGoToFieldCta), findsOneWidget);

    await tester.tap(find.text(l10n.myWorkEmptyGoToFieldCta));
    expect(taps.field, 1);
    expect(taps.create, 0);
    expect(taps.inbox, 0);
  });

  testWidgets('archived empty explains itself and offers one next step', (
    tester,
  ) async {
    final taps = _Taps();
    final l10n = await _pump(tester, MyWorkFilter.archived, taps);

    _expectExplained(l10n, MyWorkFilter.archived);

    final create = find.text(l10n.myWorkEmptyActiveCreateCta);
    final field = find.text(l10n.myWorkEmptyGoToFieldCta);
    final ctaCount = create.evaluate().length + field.evaluate().length;
    expect(ctaCount, 1, reason: 'exactly one of Create request / Go to Field');

    await tester.tap(create.evaluate().isNotEmpty ? create : field);
    expect(taps.create + taps.field, 1);
    expect(taps.inbox, 0);
  });

  testWidgets('each filter has its own sentence, distinct from its title', (
    tester,
  ) async {
    final l10n = await _pump(tester, MyWorkFilter.authored, _Taps());

    final bodies = [for (final f in _filters) _body(l10n, f)];
    expect(bodies.toSet(), hasLength(bodies.length));
    for (final f in _filters) {
      final body = _body(l10n, f);
      expect(body.trim(), isNotEmpty);
      expect(body, isNot(_title(l10n, f)));
      expect(body, isNot(l10n.myWorkEmptyActiveBody));
    }
  });

  testWidgets('Russian empty states are translated', (tester) async {
    final ru = await _pump(
      tester,
      MyWorkFilter.helpOffered,
      _Taps(),
      locale: const Locale('ru'),
    );
    final en = lookupL10n(const Locale('en'));
    final cyrillic = RegExp('[А-Яа-яЁё]');

    expect(find.text(ru.myWorkEmptyHelpOfferedBody), findsOneWidget);
    expect(find.text(ru.myWorkEmptyGoToFieldCta), findsOneWidget);
    for (final f in _filters) {
      expect(_body(ru, f), contains(cyrillic));
      expect(_body(ru, f), isNot(_body(en, f)));
    }
    expect(ru.myWorkEmptyGoToFieldCta, contains(cyrillic));
  });
}
