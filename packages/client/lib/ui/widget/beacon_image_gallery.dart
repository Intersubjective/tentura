import 'dart:async';

import 'package:flutter/material.dart';
import 'package:blurhash_shader/blurhash_shader.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'beacon_gallery_viewer.dart';

class BeaconImageGallery extends StatefulWidget {
  const BeaconImageGallery({
    required this.beacon,

    /// When set, constrains gallery height (e.g. beacon overview operational layout).
    this.maxHeight,
    super.key,
  });

  final Beacon beacon;

  /// Non-null ⇒ fixed viewport height; images use [BoxFit.cover].
  final double? maxHeight;

  @override
  State<BeaconImageGallery> createState() => _BeaconImageGalleryState();
}

class _BeaconImageGalleryState extends State<BeaconImageGallery> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    unawaited(
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.beacon.images;
    final imageUrls = widget.beacon.imageUrls;
    final storageKey = widget.maxHeight == null
        ? 'beacon-gallery-${widget.beacon.id}-full'
        : 'beacon-gallery-${widget.beacon.id}-compact-${widget.maxHeight}';

    final pageView = PageView.builder(
      key: PageStorageKey<String>(storageKey),
      controller: _pageController,
      itemCount: imageUrls.length,
      onPageChanged: (i) => setState(() => _currentPage = i),
      itemBuilder: (_, index) {
        final image = images[index];
        final networkImage = Image.network(
          imageUrls[index],
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, _, _) => Image.asset(
            'images/placeholder/beacon.jpg',
            fit: BoxFit.cover,
          ),
        );

        return GestureDetector(
          onTap: () => BeaconGalleryViewer.show(
            context,
            beacon: widget.beacon,
            initialIndex: index,
          ),
          child: image.blurHash.isEmpty
              ? networkImage
              : BlurHash(image.blurHash, child: networkImage),
        );
      },
    );

    final maxH = widget.maxHeight;
    const radius = BorderRadius.vertical(top: Radius.circular(16));
    final Widget viewport = maxH != null
        ? SizedBox(
            height: maxH,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: radius,
              child: pageView,
            ),
          )
        : ClipRRect(
            borderRadius: radius,
            child: AspectRatio(
              aspectRatio: images.first.height > 0
                  ? images.first.width / images.first.height
                  : 4 / 3,
              child: pageView,
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        viewport,
        if (imageUrls.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: kSpacingSmall),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (maxH != null)
                  Padding(
                    padding: const EdgeInsets.only(right: kSpacingSmall),
                    child: Text(
                      '${_currentPage + 1}/${imageUrls.length}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ...List.generate(
                  imageUrls.length,
                  (index) => GestureDetector(
                    onTap: () => _goTo(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentPage == index ? 10 : 7,
                      height: _currentPage == index ? 10 : 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentPage == index
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
