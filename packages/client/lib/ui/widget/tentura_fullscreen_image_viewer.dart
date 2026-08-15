import 'dart:async';

import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';

/// A single image entry for [TenturaFullscreenImageViewer].
@immutable
class TenturaGalleryImage {
  const TenturaGalleryImage({
    required this.url,
    this.blurHash = '',
  });

  final String url;
  final String blurHash;
}

/// Full-screen image gallery with pinch/zoom ([BoxFit.contain], uncropped).
class TenturaFullscreenImageViewer extends StatefulWidget {
  const TenturaFullscreenImageViewer({
    required this.images,
    this.initialIndex = 0,
    super.key,
  });

  final List<TenturaGalleryImage> images;
  final int initialIndex;

  static Future<void> show(
    BuildContext context, {
    required List<TenturaGalleryImage> images,
    int initialIndex = 0,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TenturaFullscreenImageViewer(
            images: images,
            initialIndex: initialIndex,
          ),
        ),
      );

  @override
  State<TenturaFullscreenImageViewer> createState() =>
      _TenturaFullscreenImageViewerState();
}

class _TenturaFullscreenImageViewerState
    extends State<TenturaFullscreenImageViewer> {
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
    final clamped = index.clamp(0, widget.images.length - 1);
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
    final images = widget.images;
    final tt = context.tt;
    final chromeBg = tt.bg;
    final chromeFg = tt.text;
    final chromeMuted = tt.textMuted;

    if (images.isEmpty) {
      return Scaffold(
        backgroundColor: chromeBg,
        appBar: AppBar(
          backgroundColor: chromeBg,
          foregroundColor: chromeFg,
        ),
        body: Center(
          child: Icon(Icons.photo_outlined, color: chromeMuted, size: 64),
        ),
      );
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: chromeBg,
        appBar: AppBar(
          backgroundColor: chromeBg,
          foregroundColor: chromeFg,
          title: images.length > 1
              ? Text(
                  '${_currentIndex + 1} / ${images.length}',
                  style: TenturaText.body(chromeFg),
                )
              : null,
        ),
        body: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: images.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (_, index) {
                final image = images[index];
                final networkImage = Image.network(
                  image.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(
                      Icons.broken_image,
                      color: chromeMuted,
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
                        color: chromeMuted,
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
            if (images.length > 1) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: Icon(
                      Icons.chevron_left,
                      color: chromeMuted,
                      size: 40,
                    ),
                    onPressed: _currentIndex > 0
                        ? () => _goTo(_currentIndex - 1)
                        : null,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    icon: Icon(
                      Icons.chevron_right,
                      color: chromeMuted,
                      size: 40,
                    ),
                    onPressed: _currentIndex < images.length - 1
                        ? () => _goTo(_currentIndex + 1)
                        : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
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
                              ? chromeFg
                              : chromeMuted,
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

/// Opens the profile avatar in fullscreen when [profile] has a photo.
Future<void> openProfileAvatarFullscreen(
  BuildContext context,
  Profile profile,
) {
  if (!profile.hasAvatar) return Future.value();
  return TenturaFullscreenImageViewer.show(
    context,
    images: [
      TenturaGalleryImage(
        url: profile.avatarUrl,
        blurHash: profile.image?.blurHash ?? '',
      ),
    ],
  );
}
