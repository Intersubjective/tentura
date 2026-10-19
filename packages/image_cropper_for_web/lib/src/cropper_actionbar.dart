import 'package:flutter/material.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';

import 'cropper_translations.dart';

class CropperActionBar extends StatefulWidget {
  final Function(RotationAngle) onRotate;
  final Function(num) onScale;
  final WebTranslations translations;
  final WebThemeData? themeData;
  final bool enabled;

  const CropperActionBar({
    super.key,
    required this.onRotate,
    required this.onScale,
    required this.translations,
    this.themeData,
    this.enabled = true,
  });

  @override
  State<CropperActionBar> createState() => _CropperActionBarState();
}

class _CropperActionBarState extends State<CropperActionBar> {
  double _scaleValue = 1;

  static String _formatScale(double value) =>
      '${value.toStringAsFixed(1)}\u00d7';

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.themeData?.rotateIconColor;
    final themeData = iconColor != null
        ? Theme.of(context).copyWith(
            iconTheme: IconThemeData(color: iconColor),
            iconButtonTheme: IconButtonThemeData(
              style: ButtonStyle(
                foregroundColor:
                    WidgetStateColor.resolveWith((states) => iconColor),
              ),
            ),
          )
        : Theme.of(context);
    final enabled = widget.enabled;
    final translations = widget.translations;
    final zoomLabel = translations is CropperWebTranslations
        ? translations.zoomLabel
        : CropperWebTranslations.defaultZoomLabel;
    return Theme(
      data: themeData,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: enabled
                ? () {
                    widget.onRotate(RotationAngle.counterClockwise90);
                  }
                : null,
            tooltip: widget.translations.rotateLeftTooltip,
            icon: Icon(
              widget.themeData?.rotateLeftIcon ??
                  Icons.rotate_90_degrees_ccw_rounded,
            ),
          ),
          Expanded(
            // One semantics node: label = zoom label, value = factor (1.0×).
            child: MergeSemantics(
              child: Row(
                children: [
                  const Icon(Icons.zoom_in),
                  const SizedBox(width: 4),
                  Text(zoomLabel),
                  Expanded(
                    child: Slider(
                      value: _scaleValue,
                      min: widget.themeData?.scaleSliderMinValue ?? 1.0,
                      max: widget.themeData?.scaleSliderMaxValue ?? 3.0,
                      divisions: widget.themeData?.scaleSliderDivisions,
                      semanticFormatterCallback: _formatScale,
                      onChanged: enabled
                          ? (value) {
                              setState(() {
                                _scaleValue = value;
                              });
                              widget.onScale(value);
                            }
                          : null,
                    ),
                  ),
                  // Announced via the slider value; shown here for sight.
                  ExcludeSemantics(
                    child: Text(
                      _formatScale(_scaleValue),
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: enabled
                ? () {
                    widget.onRotate(RotationAngle.clockwise90);
                  }
                : null,
            tooltip: widget.translations.rotateRightTooltip,
            icon: Icon(
              widget.themeData?.rotateRightIcon ??
                  Icons.rotate_90_degrees_cw_outlined,
            ),
          )
        ],
      ),
    );
  }
}
