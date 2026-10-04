
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_composer_cubit.dart';

/// The composer of this subtree, or null where none is provided.
ConstellationComposerCubit? maybeConstellationComposer(BuildContext context) {
  try {
    return context.read<ConstellationComposerCubit>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// Kind choices for starting the composer; the Post choice is gated.
List<PopupMenuEntry<BeaconKind>> constellationCreateMenuItems(L10n l10n) => [
  if (kPostsEnabled)
    PopupMenuItem(
      key: const Key('constellation.canvas.create_menu.post'),
      value: BeaconKind.post,
      child: Text(l10n.postCreateMenuPost),
    ),
  PopupMenuItem(
    key: const Key('constellation.canvas.create_menu.request'),
    value: BeaconKind.request,
    child: Text(l10n.postCreateMenuRequest),
  ),
];

/// Offers the kind menu at [globalPosition] and starts the composer at
/// [scenePosition] with the chosen kind.
Future<void> showConstellationCreateMenu(
  BuildContext context, {
  required ConstellationComposerCubit composer,
  required Offset globalPosition,
  required Offset scenePosition,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final kind = await showMenu<BeaconKind>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: constellationCreateMenuItems(L10n.of(context)!),
    popUpAnimationStyle: AnimationStyle.noAnimation,
  );
  if (kind != null) {
    composer.start(kind, scenePosition);
  }
}
