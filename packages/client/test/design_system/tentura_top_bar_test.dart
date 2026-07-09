import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
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
    expect(appBar.backgroundColor, scheme.primary);
    expect(appBar.foregroundColor, scheme.onPrimary);
    expect(appBar.automaticallyImplyLeading, isFalse);
    expect(appBar.titleSpacing, 0);
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

  testWidgets('TenturaPrimaryTabBar uses on-primary tab styling', (
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
    expect(tabBar.labelColor, scheme.onPrimary);
    expect(tabBar.indicatorColor, scheme.onPrimary);
    expect(tabBar.dividerColor, Colors.transparent);
    expect(tabBar.tabAlignment, TabAlignment.start);
  });

  testWidgets('TenturaTopBar golden matrix', (tester) async {
    tester.view.physicalSize = const Size(1000, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TenturaTheme.light(),
        home: Scaffold(
          body: RepaintBoundary(
            key: const Key('golden'),
            child: ColoredBox(
              color: TenturaTheme.light().colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GoldenSection(
                    label: 'compact',
                    size: const Size(390, 132),
                    tone: TenturaTopBarTone.primary,
                  ),
                  _GoldenSection(
                    label: 'compact',
                    size: const Size(390, 132),
                    tone: TenturaTopBarTone.surface,
                  ),
                  _GoldenSection(
                    label: 'expanded',
                    size: const Size(900, 136),
                    tone: TenturaTopBarTone.primary,
                  ),
                  _GoldenSection(
                    label: 'expanded',
                    size: const Size(900, 136),
                    tone: TenturaTopBarTone.surface,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/tentura_top_bar_matrix.png'),
    );
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

class _GoldenSection extends StatelessWidget {
  const _GoldenSection({
    required this.label,
    required this.size,
    required this.tone,
  });

  final String label;
  final Size size;
  final TenturaTopBarTone tone;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: TenturaResponsiveScope(
        child: Builder(
          builder: (context) {
            final toneLabel = tone == TenturaTopBarTone.primary
                ? 'primary'
                : 'surface';
            return DefaultTabController(
              length: 2,
              child: SizedBox(
                width: size.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GoldenBarFrame(
                      label: '$label $toneLabel plain',
                      appBar: TenturaTopBar.of(
                        context,
                        tone: tone,
                        title: Text('$label $toneLabel'),
                      ),
                    ),
                    _GoldenBarFrame(
                      label: '$label $toneLabel leading actions',
                      appBar: TenturaTopBar.of(
                        context,
                        tone: tone,
                        leading: const IconButton(
                          onPressed: null,
                          icon: Icon(Icons.arrow_back),
                        ),
                        title: const Text('Leading + actions'),
                        actions: const [
                          IconButton(onPressed: null, icon: Icon(Icons.search)),
                          IconButton(
                            onPressed: null,
                            icon: Icon(Icons.more_vert),
                          ),
                        ],
                      ),
                    ),
                    _GoldenBarFrame(
                      label: '$label $toneLabel tabs',
                      appBar: TenturaTopBar.of(
                        context,
                        tone: tone,
                        title: const Text('Tabs'),
                        bottom: const TenturaPrimaryTabBar(
                          tabs: [
                            Tab(text: 'Open'),
                            Tab(text: 'Watching'),
                          ],
                        ),
                      ),
                    ),
                    _GoldenBarFrame(
                      label: '$label $toneLabel progress',
                      appBar: TenturaTopBar.of(
                        context,
                        tone: tone,
                        title: const Text('Progress reserved'),
                        progress: TenturaTopBar.loadingBar(
                          context,
                          false,
                          tone: tone,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GoldenBarFrame extends StatelessWidget {
  const _GoldenBarFrame({
    required this.label,
    required this.appBar,
  });

  final String label;
  final PreferredSizeWidget appBar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: appBar.preferredSize.height + 32,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: appBar.preferredSize.height, child: appBar),
          SizedBox(
            height: 32,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.tt.screenHPadding,
              ),
              child: TenturaContentColumn(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
