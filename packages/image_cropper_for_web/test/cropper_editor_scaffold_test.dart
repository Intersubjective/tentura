import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper_for_web/src/cropper_editor_scaffold.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';

void main() {
  const translations = WebTranslations(
    title: 'Crop profile photo',
    rotateLeftTooltip: 'Rotate left',
    rotateRightTooltip: 'Rotate right',
    cancelButton: 'Cancel',
    cropButton: 'Save',
  );

  Widget pumpScaffold({
    required Future<String?> Function() onCrop,
    double maxCanvasSide = 400,
    Size surfaceSize = const Size(400, 700),
  }) {
    return MediaQuery(
      data: MediaQueryData(size: surfaceSize),
      child: MaterialApp(
        home: SizedBox(
          width: surfaceSize.width,
          height: surfaceSize.height,
          child: CropperEditorScaffold(
            translations: translations,
            maxCanvasSide: maxCanvasSide,
            onCrop: onCrop,
            onRotate: (_) {},
            onScale: (_) {},
            canvasBuilder: (context, side) => ColoredBox(
              key: const Key('CropperEditor.Canvas'),
              color: Colors.grey,
              child: SizedBox(width: side, height: side),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('AppBar shows Save; no footer Cancel/Crop', (tester) async {
    await tester.pumpWidget(pumpScaffold(onCrop: () async => 'blob:x'));

    expect(find.byKey(const Key('CropperEditor.Save')), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Crop'), findsNothing);
  });

  testWidgets('compact height keeps Save and canvas within slot', (
    tester,
  ) async {
    const surface = Size(360, 560);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      pumpScaffold(
        onCrop: () async => 'blob:x',
        maxCanvasSide: 500,
        surfaceSize: surface,
      ),
    );

    final save = tester.getRect(find.byKey(const Key('CropperEditor.Save')));
    final canvas = tester.getRect(find.byKey(const Key('CropperEditor.Canvas')));
    final rotateLeft = tester.getRect(
      find.byTooltip('Rotate left'),
    );

    expect(save.top, greaterThanOrEqualTo(0));
    expect(save.bottom, lessThanOrEqualTo(surface.height));
    expect(rotateLeft.bottom, lessThanOrEqualTo(surface.height));
    expect(canvas.width, lessThanOrEqualTo(500));
    expect(canvas.height, equals(canvas.width));
    // Canvas must not cover the Save button.
    expect(canvas.top, greaterThan(save.bottom - 1));
  });

  testWidgets('processing shows spinner, disables Save, blocks pop', (
    tester,
  ) async {
    final completer = Completer<String?>();
    await tester.pumpWidget(pumpScaffold(onCrop: () => completer.future));

    await tester.tap(find.byKey(const Key('CropperEditor.Save')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    final saveButton = tester.widget<TextButton>(
      find.byKey(const Key('CropperEditor.Save')),
    );
    expect(saveButton.onPressed, isNull);

    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse);

    completer.complete('blob:done');
    await tester.pumpAndSettle();
  });

  testWidgets('crop failure shows SnackBar and re-enables Save', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpScaffold(
        onCrop: () async {
          throw StateError('crop failed');
        },
      ),
    );

    await tester.tap(find.byKey(const Key('CropperEditor.Save')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('Could not save the image. Please try again.'),
      findsOneWidget,
    );

    final saveButton = tester.widget<TextButton>(
      find.byKey(const Key('CropperEditor.Save')),
    );
    expect(saveButton.onPressed, isNotNull);
  });
}
