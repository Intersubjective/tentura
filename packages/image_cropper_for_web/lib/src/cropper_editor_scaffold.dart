import 'package:flutter/material.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';

import 'cropper_actionbar.dart';

/// Web-import-free chrome for the cropper page so VM widget tests can pump it.
///
/// [canvasBuilder] receives the laid-out square side (min of remaining slot and
/// [maxCanvasSide]) so the overlay never overflows AppBar / tool chrome.
class CropperEditorScaffold extends StatefulWidget {
  const CropperEditorScaffold({
    super.key,
    required this.translations,
    required this.maxCanvasSide,
    required this.canvasBuilder,
    required this.onCrop,
    required this.onRotate,
    required this.onScale,
    this.themeData,
    this.cropErrorMessage = 'Could not save the image. Please try again.',
  });

  final WebTranslations translations;
  final double maxCanvasSide;
  final Widget Function(BuildContext context, double side) canvasBuilder;
  final Future<String?> Function() onCrop;
  final void Function(RotationAngle) onRotate;
  final void Function(num) onScale;
  final WebThemeData? themeData;
  final String cropErrorMessage;

  @override
  State<CropperEditorScaffold> createState() => CropperEditorScaffoldState();
}

@visibleForTesting
class CropperEditorScaffoldState extends State<CropperEditorScaffold> {
  bool _processing = false;

  bool get isProcessing => _processing;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processing,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.translations.title),
          leading: IconButton(
            tooltip: widget.translations.cancelButton,
            onPressed: _processing
                ? null
                : () => Navigator.of(context).pop(),
            icon: Icon(widget.themeData?.backIcon ?? Icons.close),
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: TextButton(
                key: const Key('CropperEditor.Save'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: _processing ? null : _doCrop,
                child: _processing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(widget.translations.cropButton),
                        ],
                      )
                    : Text(widget.translations.cropButton),
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = [
                    constraints.maxWidth,
                    constraints.maxHeight,
                    widget.maxCanvasSide,
                  ].reduce((a, b) => a < b ? a : b);
                  return Center(
                    child: widget.canvasBuilder(context, side),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: CropperActionBar(
                enabled: !_processing,
                onRotate: widget.onRotate,
                onScale: widget.onScale,
                translations: widget.translations,
                themeData: widget.themeData,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doCrop() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final result = await widget.onCrop();
      if (!mounted) return;
      Navigator.of(context).pop(result);
      return;
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.cropErrorMessage)),
        );
      }
    }
    if (mounted) {
      setState(() => _processing = false);
    }
  }
}
