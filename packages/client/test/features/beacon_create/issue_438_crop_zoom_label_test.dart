import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_cropper_for_web/cropper_editor.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/features/beacon_create/ui/widget/cover_crop_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #438: the web crop editor (cover thumbnail and avatar) showed a bare slider
// between the rotate buttons. Its only semantics was the raw value: the
// Slider `label` ("1.0") doubled as the semantics label and the value was the
// default percentage. It must read "Zoom" (icon + text) with the factor
// ("1.0×") both on screen and for screen readers, localized via the app.

const _translations = CropperWebTranslations(
  title: 'Adjust cover',
  rotateLeftTooltip: 'Rotate left',
  rotateRightTooltip: 'Rotate right',
  cancelButton: 'Cancel',
  cropButton: 'Save',
);

Widget _scaffold({
  WebTranslations translations = _translations,
  void Function(num)? onScale,
}) => MediaQuery(
  data: const MediaQueryData(size: Size(400, 700)),
  child: MaterialApp(
    home: SizedBox(
      width: 400,
      height: 700,
      child: CropperEditorScaffold(
        translations: translations,
        maxCanvasSide: 400,
        onCrop: () async => 'blob:x',
        onRotate: (_) {},
        onScale: onScale ?? (_) {},
        canvasBuilder: (context, side) => SizedBox(width: side, height: side),
      ),
    ),
  ),
);

/// The engine-visible (not merged-up) slider node(s).
List<SemanticsData> _sliderNodes() => find.semantics
    .byPredicate(
      (node) =>
          !node.isMergedIntoParent &&
          node.getSemanticsData().flagsCollection.isSlider,
    )
    .evaluate()
    .map((node) => node.getSemanticsData())
    .toList();

class _CapturingImages extends ImageRepository {
  List<PlatformUiSettings>? captured;

  @override
  Future<ImagePicked?> cropImageBytes(
    Uint8List bytes,
    List<PlatformUiSettings> cropUiSettings, {
    bool circularWebMask = false,
  }) async {
    captured = cropUiSettings;
    return null;
  }
}

void main() {
  group('Crop editor zoom slider is labelled with its value (#438)', () {
    testWidgets('shows a Zoom icon, the Zoom label and the 1.0× factor', (
      tester,
    ) async {
      await tester.pumpWidget(_scaffold());

      expect(find.byType(Slider), findsOneWidget);
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.textContaining('Zoom'), findsOneWidget);
      expect(find.textContaining('1.0×'), findsOneWidget);
    });

    testWidgets('slider semantics say Zoom and 1.0×, not a bare number', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_scaffold());

      final nodes = _sliderNodes();
      expect(nodes, hasLength(1));
      final slider = nodes.single;
      expect(slider.label, contains('Zoom'));
      expect(slider.label, isNot('1.0'));
      expect(slider.value, '1.0×');
      semantics.dispose();
    });

    testWidgets('moving the slider updates the shown and announced factor '
        'and still scales the image', (tester) async {
      final semantics = tester.ensureSemantics();
      final scaled = <num>[];
      await tester.pumpWidget(_scaffold(onScale: scaled.add));

      tester.widget<Slider>(find.byType(Slider)).onChanged!(2);
      await tester.pump();

      expect(scaled, [2]);
      expect(find.textContaining('2.0×'), findsOneWidget);
      expect(find.textContaining('1.0×'), findsNothing);
      final slider = _sliderNodes().single;
      expect(slider.value, '2.0×');
      expect(slider.label, contains('Zoom'));
      semantics.dispose();
    });

    testWidgets('uses the zoom label it is given (localized)', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _scaffold(
          translations: const CropperWebTranslations(
            title: 'Обложка',
            rotateLeftTooltip: 'Влево',
            rotateRightTooltip: 'Вправо',
            cancelButton: 'Отмена',
            cropButton: 'Сохранить',
            zoomLabel: 'Масштаб',
          ),
        ),
      );

      expect(find.textContaining('Масштаб'), findsOneWidget);
      expect(find.textContaining('Zoom'), findsNothing);
      expect(_sliderNodes().single.label, contains('Масштаб'));
      semantics.dispose();
    });

    testWidgets('plain WebTranslations fall back to the English Zoom label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scaffold(translations: const WebTranslations.en()),
      );

      expect(find.textContaining('Zoom'), findsOneWidget);
      expect(find.textContaining('1.0×'), findsOneWidget);
    });
  });

  group('Cover crop passes the app zoom label to the web cropper (#438)', () {
    for (final (locale, expected) in [
      (const Locale('en'), 'Zoom'),
      (const Locale('ru'), 'Масштаб'),
    ]) {
      testWidgets('${locale.languageCode}: WebUiSettings carry "$expected"', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const SizedBox(key: Key('Issue438.Host')),
          ),
        );
        await tester.pumpAndSettle();

        final host = tester.element(find.byKey(const Key('Issue438.Host')));
        final l10n = L10n.of(host)!;
        final images = _CapturingImages();
        await BeaconCoverCropUi(
          host,
          l10n,
          images: images,
        ).cropSquare(Uint8List(0));

        final web = images.captured!.whereType<WebUiSettings>().single;
        final translations = web.translations;
        expect(translations, isA<CropperWebTranslations>());
        final zoom = (translations! as CropperWebTranslations).zoomLabel;
        expect(zoom, l10n.cropZoomLabel);
        expect(zoom, expected);
      });
    }
  });
}
