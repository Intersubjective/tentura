import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blurhash_shader/blurhash_shader.dart';

import 'package:tentura/domain/entity/beacon.dart';

class BeaconGalleryViewer extends StatefulWidget {
  const BeaconGalleryViewer({
    required this.beacon,
    this.initialIndex = 0,
    super.key,
  });

  final Beacon beacon;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required Beacon beacon,
    int initialIndex = 0,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BeaconGalleryViewer(
            beacon: beacon,
            initialIndex: initialIndex,
          ),
        ),
      );

  @override
  State<BeaconGalleryViewer> createState() => _BeaconGalleryViewerState();
}

class _BeaconGalleryViewerState extends State<BeaconGalleryViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  final _focusNode = FocusNode();

  /// One controller per page so zoom/pan state does not leak across images.
  final _transformControllers = <int, TransformationController>{};

  TransformationController _controllerFor(int index) {
    return _transformControllers.putIfAbsent(index, () {
      final c = TransformationController()
        ..addListener(() {
          if (mounted) setState(() {});
        });
      return c;
    });
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    _transformControllers.clear();
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goTo(_currentIndex - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goTo(_currentIndex + 1);
    }
  }

  void _goTo(int index) {
    final clamped = index.clamp(0, widget.beacon.imageUrls.length - 1);
    if (clamped != _currentIndex) {
      unawaited(
        _pageController.animateToPage(
          clamped,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ),
      );
    }
  }

  static const _kZoomThreshold = 1.01;

  @override
  Widget build(BuildContext context) {
    final imageUrls = widget.beacon.imageUrls;
    final images = widget.beacon.images;

    if (imageUrls.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Icon(Icons.photo_outlined, color: Colors.white38, size: 64),
        ),
      );
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: imageUrls.length > 1
              ? Text(
                  '${_currentIndex + 1} / ${imageUrls.length}',
                  style: const TextStyle(color: Colors.white),
                )
              : null,
        ),
        body: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: imageUrls.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (_, index) {
                final image = images[index];
                final networkImage = Image.network(
                  imageUrls[index],
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    final indicator = Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                        color: Colors.white54,
                      ),
                    );
                    if (image.blurHash.isNotEmpty) {
                      return BlurHash(image.blurHash, child: indicator);
                    }
                    return indicator;
                  },
                );

                final tc = _controllerFor(index);
                final zoomed =
                    tc.value.getMaxScaleOnAxis() > _kZoomThreshold;

                return InteractiveViewer(
                  transformationController: tc,
                  panEnabled: zoomed,
                  minScale: 1,
                  maxScale: 4,
                  child: Center(child: networkImage),
                );
              },
            ),
            if (imageUrls.length > 1) ...[
              // Left arrow
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: const Icon(
                      Icons.chevron_left,
                      color: Colors.white54,
                      size: 40,
                    ),
                    onPressed: _currentIndex > 0
                        ? () => _goTo(_currentIndex - 1)
                        : null,
                  ),
                ),
              ),
              // Right arrow
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: const Icon(
                      Icons.chevron_right,
                      color: Colors.white54,
                      size: 40,
                    ),
                    onPressed: _currentIndex < imageUrls.length - 1
                        ? () => _goTo(_currentIndex + 1)
                        : null,
                  ),
                ),
              ),
              // Dot indicators
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    imageUrls.length,
                    (index) => GestureDetector(
                      onTap: () => _goTo(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentIndex == index ? 10 : 7,
                        height: _currentIndex == index ? 10 : 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentIndex == index
                              ? Colors.white
                              : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
