import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_cropper_for_web/cropper_editor.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/features/beacon_create/ui/widget/cover_crop_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #607 (from #438): when saving a crop failed, the web crop editor showed the
// fork's English default "Could not save the image. Please try again." in
// every locale; the app never handed it a localized message.

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

Future<BuildContext> _host(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const SizedBox(key: Key('Issue607.Host')),
    ),
  );
  await tester.pumpAndSettle();
  return tester.element(find.byKey(const Key('Issue607.Host')));
}

/// The web translations the request-cover crop hands to the cropper.
Future<WebTranslations> _coverTranslations(
  WidgetTester tester,
  Locale locale,
) async {
  final host = await _host(tester, locale);
  final images = _CapturingImages();
  await BeaconCoverCropUi(
    host,
    L10n.of(host)!,
    images: images,
  ).cropSquare(Uint8List(0));
  return images.captured!.whereType<WebUiSettings>().single.translations!;
}

void main() {
  const english = 'Could not save the image. Please try again.';
  final cyrillic = RegExp('[А-Яа-яЁё]');

  group('Crop failure message is localized (#607)', () {
    testWidgets('en: the cover crop passes the English message', (
      tester,
    ) async {
      final translations = await _coverTranslations(
        tester,
        const Locale('en'),
      );

      expect(translations, isA<CropperWebTranslations>());
      expect(
        (translations as CropperWebTranslations).cropErrorMessage,
        english,
      );
    });

    testWidgets('ru: the cover crop passes a Russian message', (
      tester,
    ) async {
      final translations = await _coverTranslations(
        tester,
        const Locale('ru'),
      );

      final message = (translations as CropperWebTranslations).cropErrorMessage;
      expect(message, contains(cyrillic));
      expect(message, isNot(english));
    });

    testWidgets('ru: a failed save shows the Russian SnackBar text', (
      tester,
    ) async {
      final translations = await _coverTranslations(
        tester,
        const Locale('ru'),
      );
      final ru = lookupL10n(const Locale('ru'));

      await tester.pumpWidget(
        MaterialApp(
          home: CropperEditorScaffold(
            translations: translations,
            maxCanvasSide: 300,
            onCrop: () async => throw StateError('crop failed'),
            onRotate: (_) {},
            onScale: (_) {},
            canvasBuilder: (context, side) =>
                SizedBox(width: side, height: side),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('CropperEditor.Save')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(ru.cropSaveError), findsOneWidget);
      expect(find.text(english), findsNothing);
    });
  });
}
