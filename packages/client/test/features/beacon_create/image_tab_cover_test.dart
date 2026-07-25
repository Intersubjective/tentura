import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/widget/image_tab.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

const _serverA = ImageEntity(id: 'srv-a', authorId: 'author-1');
const _serverB = ImageEntity(id: 'srv-b', authorId: 'author-1');

ImagePicked _picked(String fileName) => ImagePicked(
  bytes: Uint8List.fromList(kTinyPng),
  fileName: fileName,
);

Widget _harness(BeaconCreateCubit cubit, {double width = 400}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: Scaffold(
    body: SizedBox(
      width: width,
      child: BlocProvider<BeaconCreateCubit>.value(
        value: cubit,
        child: const ImageTab(),
      ),
    ),
  ),
);

void main() {
  late FakeBeaconWritePort write;
  late FakeBeaconImagePort images;
  late BeaconCreateCubit cubit;

  setUp(() {
    write = FakeBeaconWritePort();
    images = FakeBeaconImagePort();
    cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write, images: images),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
  });

  /// Both cards must be laid out at once, so the surface is taller than the
  /// 800×600 test default.
  Future<void> pumpTab(
    WidgetTester tester, {
    double width = 400,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_harness(cubit, width: width));
    await tester.pumpAndSettle();
  }

  Future<void> seedServerImages(
    List<ImageEntity> seeded, {
    required String coverKey,
  }) async {
    write.beacon = Beacon.empty.copyWith(
      id: 'b-1',
      status: BeaconStatus.open,
      images: seeded,
      coverImageId: coverKey,
    );
    await cubit.loadEdit('b-1');
  }

  testWidgets('the selected cover is marked, others offer the action', (
    tester,
  ) async {
    await seedServerImages([_serverA, _serverB], coverKey: 'srv-a');

    await pumpTab(tester);

    expect(find.text('Selected cover'), findsOneWidget);
    expect(find.text('Use as cover'), findsOneWidget);
    expect(
      find.byKey(const Key('BeaconImage.UseAsCover.srv-b')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('BeaconImage.AdjustCover.srv-a')),
      findsOneWidget,
    );
  });

  testWidgets('the cover marking carries a semantic label, not colour alone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await seedServerImages([_serverA], coverKey: 'srv-a');

    await pumpTab(tester);

    expect(
      tester.getSemantics(find.text('Selected cover')).label,
      contains('Selected cover'),
    );
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('"Use as cover" selects that image and the photo preference', (
    tester,
  ) async {
    await seedServerImages([_serverA, _serverB], coverKey: 'srv-a');
    cubit.selectPhotoCoverSource();

    await pumpTab(tester);
    await tester.tap(find.byKey(const Key('BeaconImage.UseAsCover.srv-b')));
    await tester.pumpAndSettle();

    expect(cubit.state.coverKey, 'srv-b');
    expect(cubit.state.coverSource, BeaconCoverSource.photo);
    expect(
      find.byKey(const Key('BeaconImage.UseAsCover.srv-a')),
      findsOneWidget,
    );
  });

  testWidgets('removing the cover moves the marking to the first remaining', (
    tester,
  ) async {
    await seedServerImages([_serverA, _serverB], coverKey: 'srv-a');

    await pumpTab(tester);
    await tester.tap(find.byKey(const Key('BeaconImage.Remove.srv-a')));
    await tester.pumpAndSettle();

    expect(cubit.state.coverKey, 'srv-b');
    expect(
      find.byKey(const Key('BeaconImage.AdjustCover.srv-b')),
      findsOneWidget,
    );
    expect(find.text('Use as cover'), findsNothing);
  });

  testWidgets('locally picked images are addressed by their local key', (
    tester,
  ) async {
    images.picked = [_picked('a.jpg'), _picked('b.jpg')];
    await cubit.pickImages();
    final keys = cubit.state.images.map((e) => e.key).toList();

    await pumpTab(tester);

    expect(
      find.byKey(Key('BeaconImage.UseAsCover.${keys.last}')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('BeaconImage.UseAsCover.${keys.last}')));
    await tester.pumpAndSettle();

    expect(cubit.state.coverKey, keys.last);
  });

  testWidgets('the grid layout marks the cover the same way', (tester) async {
    await seedServerImages([_serverA, _serverB], coverKey: 'srv-b');

    await pumpTab(tester, width: 900);

    expect(find.text('Selected cover'), findsOneWidget);
    expect(
      find.byKey(const Key('BeaconImage.AdjustCover.srv-b')),
      findsOneWidget,
    );
  });
}
