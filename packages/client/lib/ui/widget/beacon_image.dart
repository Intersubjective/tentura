import 'package:flutter/material.dart';
import 'package:blurhash_shader/blurhash_shader.dart';

import 'package:tentura/domain/entity/beacon.dart';

import 'beacon_gallery_viewer.dart';

/// Key of the token-coloured box a cover slot paints until its image shows.
const beaconImagePlaceholderKey = Key('beacon-image-placeholder');

/// The cover slot's fill while its image loads or after it failed (#816):
/// painted on the first frame, so the slot is never an empty box.
class BeaconImagePlaceholder extends StatelessWidget {
  const BeaconImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: beaconImagePlaceholderKey,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const SizedBox.expand(),
  );
}

/// Fades a decoded network image in over whatever sits below it (#816); an
/// image already in memory shows at once.
Widget beaconImageFadeInFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) => wasSynchronouslyLoaded
    ? child
    : AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: Durations.short4,
        curve: Easing.standardDecelerate,
        child: child,
      );

/// [beaconImageFadeInFrame] over a [BeaconImagePlaceholder], for image slots
/// with nothing of their own below the image (identity tiles).
Widget beaconImageFadeInOverPlaceholder(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) => wasSynchronouslyLoaded
    ? child
    : Stack(
        fit: StackFit.expand,
        children: [
          const BeaconImagePlaceholder(),
          beaconImageFadeInFrame(context, child, frame, false),
        ],
      );

class BeaconImage extends StatelessWidget {
  const BeaconImage({
    required this.beacon,
    this.boxFit = BoxFit.cover,
    this.enableGalleryTap = false,
    this.imageProviderFor = _networkProvider,
    super.key,
  });

  final Beacon beacon;
  final BoxFit boxFit;
  final bool enableGalleryTap;

  /// The provider for an image URL; tests swap it.
  final ImageProvider Function(String url) imageProviderFor;

  static ImageProvider _networkProvider(String url) => NetworkImage(url);

  @override
  Widget build(BuildContext context) {
    final ordered = beacon.displayImages;
    if (ordered.isEmpty) return const BeaconImagePlaceholder();

    final image = ordered.first;
    // The slot keeps the image's shape from the first frame, so the card
    // does not shift when the image arrives (#816).
    final imageWidget = AspectRatio(
      aspectRatio: image.height > 0 && image.width > 0
          ? image.width / image.height
          : 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Below the BlurHash: a slow or failing shader never leaves an
          // empty box (#816).
          const BeaconImagePlaceholder(),
          if (image.blurHash.isNotEmpty) BlurHash(image.blurHash),
          Image(
            image: imageProviderFor(beacon.urlForImage(image)),
            fit: boxFit,
            frameBuilder: beaconImageFadeInFrame,
            errorBuilder: (_, _, _) => const BeaconImagePlaceholder(),
          ),
        ],
      ),
    );

    if (!enableGalleryTap) return imageWidget;

    return GestureDetector(
      onTap: () => BeaconGalleryViewer.show(
        context,
        beacon: beacon,
      ),
      child: imageWidget,
    );
  }
}
