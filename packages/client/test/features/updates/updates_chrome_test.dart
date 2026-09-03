import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_app_bar.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_search_field.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('compact chrome hides search until icon tap', (tester) async {
    var open = false;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.dark(),
        localizationsDelegates: L10n.localizationsDelegates,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: TenturaResponsiveScope(
            child: StatefulBuilder(
              builder: (context, setState) {
                final compact = context.windowClass == WindowClass.compact;
                return Scaffold(
                  appBar: TenturaTopBar.of(
                    context,
                    title: const SizedBox.shrink(),
                    row: UpdatesFeedAppBarRow(
                      title: 'Updates',
                      markAllLabel: 'Read all',
                      hasUnread: true,
                      onMarkAll: () {},
                      showSearchIcon: compact,
                      searchOpen: open,
                      onSearchPressed: () => setState(() => open = !open),
                      searchTooltip: 'Search',
                    ),
                  ),
                  body: Column(
                    children: [
                      if (!compact || open)
                        UpdatesFeedSearchField(
                          controller: controller,
                          hintText: 'Search updates',
                          onChanged: (_) {},
                          onClear: () {},
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(UpdatesFeedSearchField), findsNothing);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    expect(find.byType(UpdatesFeedSearchField), findsOneWidget);
  });

  testWidgets('regular width shows search without icon', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 800)),
          child: TenturaResponsiveScope(
            child: Builder(
              builder: (context) {
                final compact = context.windowClass == WindowClass.compact;
                return Scaffold(
                  appBar: TenturaTopBar.of(
                    context,
                    title: const SizedBox.shrink(),
                    row: UpdatesFeedAppBarRow(
                      title: 'Updates',
                      markAllLabel: 'Read all',
                      hasUnread: false,
                      onMarkAll: () {},
                      showSearchIcon: compact,
                      searchOpen: false,
                      onSearchPressed: () {},
                      searchTooltip: 'Search',
                    ),
                  ),
                  body: compact
                      ? const SizedBox.shrink()
                      : UpdatesFeedSearchField(
                          controller: controller,
                          hintText: 'Search updates',
                          onChanged: (_) {},
                          onClear: () {},
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(UpdatesFeedSearchField), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
  });
}
