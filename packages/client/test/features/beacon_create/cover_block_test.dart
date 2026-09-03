import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/cover_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

ImagePicked _picked(String fileName) => ImagePicked(
  bytes: Uint8List.fromList(kTinyPng),
  fileName: fileName,
);

Widget _harness(BeaconCreateCubit cubit, {double width = 800}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, 900)),
    child: Scaffold(
      body: BlocProvider<BeaconCreateCubit>.value(
        value: cubit,
        child: SizedBox(
          width: width,
          child: CoverBlock(onManageCapabilities: () {}),
        ),
      ),
    ),
  ),
);

void main() {
  late FakeBeaconImagePort images;
  late BeaconCreateCubit cubit;

  setUp(() {
    images = FakeBeaconImagePort();
    cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(images: images),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
  });

  Finder photoButton() => find.byKey(const Key('BeaconCover.SourcePhoto'));
  Finder symbolButton() => find.byKey(const Key('BeaconCover.SourceSymbol'));

  /// Selected source uses [FilledButton.tonal]; unselected uses [OutlinedButton].
  bool isTonalSelected(WidgetTester tester, Key key) {
    final filled = find.byWidgetPredicate(
      (w) => w is FilledButton && w.key == key,
    );
    return tester.widgetList(filled).isNotEmpty;
  }

  testWidgets('with no photos and no capabilities photo stays selected', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(cubit));

    expect(find.text('Request cover'), findsOneWidget);
    expect(find.byKey(const Key('BeaconCover.SourceControl')), findsOneWidget);
    expect(
      isTonalSelected(tester, const Key('BeaconCover.SourcePhoto')),
      isTrue,
    );
    expect(
      isTonalSelected(tester, const Key('BeaconCover.SourceSymbol')),
      isFalse,
    );
    expect(find.textContaining('Add a capability first.'), findsOneWidget);
    expect(find.byType(TenturaCapabilityGlyph), findsNothing);
  });

  testWidgets('a valid primary shows the symbol while photo stays selected', (
    tester,
  ) async {
    cubit.setNeeds({'transport'});
    await tester.pumpWidget(_harness(cubit));

    expect(
      isTonalSelected(tester, const Key('BeaconCover.SourcePhoto')),
      isTrue,
    );
    expect(find.byType(TenturaCapabilityGlyph), findsOneWidget);
    expect(
      find.text('No cover photo yet — showing the Transport symbol.'),
      findsOneWidget,
    );
  });

  testWidgets('selecting symbol keeps the preference and names the capability', (
    tester,
  ) async {
    cubit.setNeeds({'transport'});
    await tester.pumpWidget(_harness(cubit));

    await tester.tap(symbolButton());
    await tester.pumpAndSettle();

    expect(cubit.state.coverSource, BeaconCoverSource.symbol);
    expect(find.text('Choose a symbol'), findsOneWidget);

    await tester.tap(find.byKey(const Key('BeaconCover.Symbol.transport')));
    await tester.pumpAndSettle();

    expect(
      isTonalSelected(tester, const Key('BeaconCover.SourceSymbol')),
      isTrue,
    );
    expect(find.text('Showing the Transport symbol.'), findsOneWidget);
    expect(find.text('Change symbol'), findsOneWidget);
  });

  testWidgets('selecting symbol with several capabilities opens the sheet', (
    tester,
  ) async {
    cubit.setNeeds({'transport', 'food'});
    await tester.pumpWidget(_harness(cubit));

    await tester.tap(symbolButton());
    await tester.pumpAndSettle();

    expect(find.text('Choose a symbol'), findsOneWidget);
    expect(find.byKey(const Key('BeaconCover.Symbol.food')), findsOneWidget);

    await tester.tap(find.byKey(const Key('BeaconCover.Symbol.food')));
    await tester.pumpAndSettle();

    expect(cubit.state.primaryNeedSlug, 'food');
    expect(cubit.state.coverSource, BeaconCoverSource.symbol);
  });

  testWidgets('symbol with no capabilities opens the empty sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(cubit));

    await tester.tap(symbolButton());
    await tester.pumpAndSettle();

    expect(cubit.state.coverSource, BeaconCoverSource.photo);
    expect(find.text('Choose a symbol'), findsOneWidget);
  });

  testWidgets('tapping photo opens the cover picker', (tester) async {
    images.picked = [_picked('a.jpg')];
    await tester.pumpWidget(_harness(cubit));

    await tester.tap(photoButton());
    await tester.pumpAndSettle();

    expect(cubit.state.images, hasLength(1));
    expect(cubit.state.coverKey, cubit.state.images.single.key);
    expect(cubit.state.coverSource, BeaconCoverSource.photo);
  });

  testWidgets('re-tapping photo while selected still picks', (tester) async {
    images.picked = [_picked('a.jpg'), _picked('b.jpg')];
    await tester.pumpWidget(_harness(cubit));

    await tester.tap(photoButton());
    await tester.pumpAndSettle();
    expect(cubit.state.images, hasLength(2));
    final firstCover = cubit.state.coverKey;

    images.picked = [_picked('c.jpg')];
    await tester.tap(photoButton());
    await tester.pumpAndSettle();

    expect(cubit.state.images, hasLength(3));
    expect(cubit.state.coverKey, isNot(firstCover));
    expect(cubit.state.coverSource, BeaconCoverSource.photo);
  });

  testWidgets('tapping the preview picks a cover photo', (tester) async {
    images.picked = [_picked('a.jpg')];
    await tester.pumpWidget(_harness(cubit));

    await tester.tap(find.byKey(const Key('BeaconCover.Preview')));
    await tester.pumpAndSettle();

    expect(cubit.state.images, hasLength(1));
    expect(cubit.state.coverKey, cubit.state.images.single.key);
    expect(cubit.state.coverSource, BeaconCoverSource.photo);
    expect(
      find.text(
        'Tap the preview to choose or replace the cover photo. '
        'The full photo stays on the request; cropping affects only the small card.',
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a symbol preference keeps the stored photo selection', (
    tester,
  ) async {
    images.picked = [_picked('a.jpg')];
    await tester.pumpWidget(_harness(cubit));
    await tester.tap(find.byKey(const Key('BeaconCover.Preview')));
    await tester.pumpAndSettle();
    final coverKey = cubit.state.coverKey;

    cubit.setNeeds({'transport'});
    await tester.pumpAndSettle();
    await tester.tap(symbolButton());
    await tester.pumpAndSettle();

    expect(cubit.state.coverKey, coverKey);
    expect(cubit.state.coverSource, BeaconCoverSource.symbol);
    // Preview + sheet list both paint a glyph while the sheet is open.
    expect(find.byType(TenturaCapabilityGlyph), findsWidgets);
  });

  testWidgets('the block lays out at compact width and text scale 2.0', (
    tester,
  ) async {
    cubit.setNeeds({'transport'});
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: BlocProvider<BeaconCreateCubit>.value(
                value: cubit,
                child: SizedBox(
                  width: 320,
                  child: CoverBlock(onManageCapabilities: () {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Request cover'), findsOneWidget);
  });
}
