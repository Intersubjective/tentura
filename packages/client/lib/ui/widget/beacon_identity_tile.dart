import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_cover.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Resolved request identity: cover photo, capability symbol, or neutral glyph.
class BeaconIdentityTile extends StatelessWidget {
  const BeaconIdentityTile({
    required this.beacon,
    this.size = 48,
    super.key,
  });

  final Beacon beacon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final identity = beacon.resolveIdentity(allowPhoto: true);
    return TenturaIdentityTileFrame(
      size: size,
      semanticsLabel: _semanticsLabel(context, identity),
      child: _content(context, identity),
    );
  }

  String _semanticsLabel(BuildContext context, BeaconIdentity identity) {
    if (identity is! BeaconIdentitySymbol) return beacon.title;
    final l10n = L10n.of(context);
    if (l10n == null) return beacon.title;
    return '${beacon.title}, ${identity.tag.labelOf(l10n)}';
  }

  Widget _content(BuildContext context, BeaconIdentity identity) =>
      switch (identity) {
        BeaconIdentityPhoto(:final image) => _photo(context, image),
        BeaconIdentitySymbol(:final tag) => TenturaCapabilityGlyph(
          tag: tag,
          size: size,
        ),
        BeaconIdentityNeutral() => _neutral(context),
      };

  /// Photo failure: thumb → full cover → symbol/neutral.
  Widget _photo(BuildContext context, ImageEntity image) {
    final cacheExtent = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final bytes = image.imageBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: size,
        height: size,
        cacheWidth: cacheExtent,
        cacheHeight: cacheExtent,
        errorBuilder: (_, _, _) => _photoErrorFallback(context, image),
      );
    }
    return Image.network(
      beacon.urlForImage(image),
      fit: BoxFit.cover,
      width: size,
      height: size,
      cacheWidth: cacheExtent,
      cacheHeight: cacheExtent,
      errorBuilder: (_, _, _) => _photoErrorFallback(context, image),
    );
  }

  Widget _photoErrorFallback(BuildContext context, ImageEntity failed) {
    final thumb = beacon.coverThumb;
    final cover = beacon.coverImage;
    if (thumb != null &&
        failed.key == thumb.key &&
        cover != null &&
        cover.key != thumb.key) {
      return _photo(context, cover);
    }
    return _content(context, beacon.resolveIdentity(allowPhoto: false));
  }

  Widget _neutral(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.campaign_outlined,
          size: size * 0.52,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
