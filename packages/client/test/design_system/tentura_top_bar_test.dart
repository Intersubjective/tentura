import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  testWidgets('the account entry sits at one spot with actions or a row', (
    tester,
  ) async {
    const accountKey = Key('account');
    Future<Rect> accountRect({required bool customRow}) async {
      await tester.pumpWidget(
        _TopBarHarness(
          size: const Size(390, 240),
          builder: (context) => Scaffold(
            appBar: TenturaTopBar.of(
              context,
              title: const Text('Screen'),
              actions: customRow
                  ? null
                  : [IconButton(onPressed: () {}, icon: const Icon(Icons.add))],
              row: customRow
                  ? Row(
                      children: [
                        const Expanded(child: Text('Screen')),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    )
                  : null,
              account: IconButton(
                key: accountKey,
                onPressed: () {},
                icon: const Icon(Icons.person),
              ),
            ),
            body: const SizedBox(),
          ),
        ),
      );
      return tester.getRect(find.byKey(accountKey));
    }

    final withActions = await accountRect(customRow: false);
    final withRow = await accountRect(customRow: true);
    expect(withRow, withActions);
    // The glyph, not the touch target, sits on the screen gutter.
    final glyph = tester.getRect(find.byIcon(Icons.person));
    final bar = tester.getRect(find.byType(AppBar));
    final gutter = tester.element(find.byType(AppBar)).tt.screenHPadding;
    expect(glyph.right, closeTo(bar.right - gutter, 1));
  });

  testWidgets('TenturaTopBar captures token height and tone colors', (
    tester,
  ) async {
    late PreferredSizeWidget bar;

    await tester.pumpWidget(
      _TopBarHarness(
        size: const Size(390, 240),
        builder: (context) {
          bar = TenturaTopBar.of(
            context,
            tone: TenturaTopBarTone.primary,
            title: const Text('Requests'),
          );
          return Scaffold(appBar: bar, body: const SizedBox());
        },
      ),
    );

    expect(bar.preferredSize, const Size.fromHeight(56));
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final scheme = Theme.of(
      tester.element(find.text('Requests')),
    ).colorScheme;
    // Tab-root bars render on surface; brand is for actions (#195).
    expect(appBar.backgroundColor, scheme.surface);
    expect(appBar.foregroundColor, scheme.onSurface);
    expect(appBar.automaticallyImplyLeading, isFalse);
    expect(appBar.titleSpacing, 0);
  });

  testWidgets('primary top bar action icons use onSurface in both themes', (
    tester,
  ) async {
    Future<Color?> actionForeground(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 240)),
            child: TenturaResponsiveScope(
              child: Builder(
                builder: (context) => Scaffold(
                  appBar: TenturaTopBar.of(
                    context,
                    tone: TenturaTopBarTone.primary,
                    title: const Text('Updates'),
                    actions: [
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.done_all),
                      ),
                    ],
                  ),
                  body: const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final iconContext = tester.element(find.byIcon(Icons.done_all));
      final style = IconButtonTheme.of(iconContext).style;
      return style?.foregroundColor?.resolve(const <WidgetState>{});
    }

    final lightInk = TenturaTheme.light().colorScheme.onSurface;
    final darkInk = TenturaTheme.dark().colorScheme.onSurface;
    expect(await actionForeground(TenturaTheme.light()), lightInk);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(await actionForeground(TenturaTheme.dark()), darkInk);
  });

  testWidgets('TenturaTopBar reserves progress height', (tester) async {
    late PreferredSizeWidget bar;

    await tester.pumpWidget(
      _TopBarHarness(
        size: const Size(700, 280),
        builder: (context) {
          bar = TenturaTopBar.of(
            context,
            title: const Text('Profile'),
            progress: TenturaTopBar.loadingBar(context, false),
          );
          return Scaffold(appBar: bar, body: const SizedBox());
        },
      ),
    );

    expect(bar.preferredSize, const Size.fromHeight(64));
  });

  testWidgets('TenturaTopBar aligns content to expanded content column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TopBarHarness(
        size: const Size(1280, 360),
        builder: (context) => Scaffold(
          appBar: TenturaTopBar.of(
            context,
            title: const Text('Aligned title', key: Key('title')),
            actions: const [
              IconButton(
                key: Key('lastAction'),
                onPressed: null,
                icon: Icon(Icons.search),
              ),
            ],
          ),
          body: SafeArea(
            minimum: EdgeInsets.symmetric(
              horizontal: context.tt.screenHPadding,
            ),
            child: const TenturaContentColumn(
              child: DecoratedBox(
                key: Key('bodyColumn'),
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(BorderSide()),
                ),
                child: SizedBox(width: double.infinity, height: 120),
              ),
            ),
          ),
        ),
      ),
    );

    final bodyLeft = tester.getTopLeft(find.byKey(const Key('bodyColumn'))).dx;
    final titleLeft = tester.getTopLeft(find.byKey(const Key('title'))).dx;
    expect(titleLeft, moreOrLessEquals(bodyLeft, epsilon: 1));

    final bodyRight = tester
        .getTopRight(find.byKey(const Key('bodyColumn')))
        .dx;
    final actionIconRight = tester.getTopRight(find.byIcon(Icons.search)).dx;
    expect(actionIconRight, moreOrLessEquals(bodyRight, epsilon: 1));
  });

  testWidgets('TenturaTopBar accepts Expanded title rows', (tester) async {
    await tester.pumpWidget(
      _TopBarHarness(
        size: const Size(390, 240),
        builder: (context) => Scaffold(
          appBar: TenturaTopBar.of(
            context,
            leading: const IconButton(
              onPressed: null,
              icon: Icon(Icons.arrow_back),
            ),
            title: const Row(
              children: [
                Expanded(child: Text('Flexible title that must not break')),
                Icon(Icons.lock, size: 16),
              ],
            ),
            actions: const [
              IconButton(onPressed: null, icon: Icon(Icons.more_vert)),
            ],
          ),
          body: const SizedBox(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Flexible title that must not break'), findsOneWidget);
  });

  testWidgets('TenturaTopBar trailing actions do not overflow on compact', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TopBarHarness(
        size: const Size(390, 240),
        builder: (context) => Scaffold(
          appBar: TenturaTopBar.of(
            context,
            leading: const IconButton(
              onPressed: null,
              icon: Icon(Icons.arrow_back),
            ),
            title: const Text('Leading + actions'),
            actions: const [
              IconButton(onPressed: null, icon: Icon(Icons.search)),
              IconButton(onPressed: null, icon: Icon(Icons.more_vert)),
            ],
          ),
          body: const SizedBox(),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'TenturaTopBar long text actions do not cover close on compact',
    (tester) async {
      tester.view.physicalSize = const Size(390, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var closed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 812),
              padding: EdgeInsets.only(top: 47, bottom: 34),
            ),
            child: TenturaResponsiveScope(
              child: Builder(
                builder: (context) {
                  final tt = context.tt;
                  final actionButtonStyle = TextButton.styleFrom(
                    minimumSize: Size(0, tt.buttonHeight),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                  return Scaffold(
                    appBar: TenturaTopBar.of(
                      context,
                      centerTitle: true,
                      leading: CloseButton(
                        key: const Key('close'),
                        onPressed: () => closed = true,
                      ),
                      trailingIsIcon: false,
                      title: const Text('Создать запрос'),
                      actions: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              key: const Key('save'),
                              style: actionButtonStyle,
                              onPressed: () {},
                              child: const Text('Сохранить черновик'),
                            ),
                            TextButton(
                              key: const Key('live'),
                              style: actionButtonStyle,
                              onPressed: () {},
                              child: const Text('Запустить'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    body: const SizedBox(),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      final closeRect = tester.getRect(find.byKey(const Key('close')));
      final saveRect = tester.getRect(find.byKey(const Key('save')));
      final liveRect = tester.getRect(find.byKey(const Key('live')));
      expect(closeRect.overlaps(saveRect), isFalse);
      expect(closeRect.overlaps(liveRect), isFalse);

      await tester.tapAt(closeRect.center);
      await tester.pump();
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('TenturaPrimaryTabBar marks selection in brand on surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TopBarHarness(
        size: const Size(390, 260),
        builder: (context) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: TenturaTopBar.of(
              context,
              tone: TenturaTopBarTone.primary,
              title: const SizedBox.shrink(),
              bottom: const TenturaPrimaryTabBar(
                tabs: [
                  Tab(text: 'Open'),
                  Tab(text: 'Closed'),
                ],
              ),
            ),
            body: const SizedBox(),
          ),
        ),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final scheme = Theme.of(tester.element(find.byType(TabBar))).colorScheme;
    expect(tabBar.labelColor, scheme.primary);
    expect(tabBar.unselectedLabelColor, scheme.onSurfaceVariant);
    expect(tabBar.indicatorColor, scheme.primary);
    expect(tabBar.dividerColor, Colors.transparent);
    expect(tabBar.tabAlignment, TabAlignment.start);
  });
}

class _TopBarHarness extends StatelessWidget {
  const _TopBarHarness({
    required this.size,
    required this.builder,
  });

  final Size size;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Builder(builder: builder),
        ),
      ),
    );
  }
}
