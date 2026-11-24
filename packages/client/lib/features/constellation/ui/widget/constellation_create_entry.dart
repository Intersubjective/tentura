import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/phantoms/ui/widget/phantom_create_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/constellation_layout.dart';
import '../bloc/constellation_composer_cubit.dart';
import '../bloc/constellation_cubit.dart';

/// The composer of this subtree, or null where none is provided.
ConstellationComposerCubit? maybeConstellationComposer(BuildContext context) {
  try {
    return context.read<ConstellationComposerCubit>();
  } on ProviderNotFoundException {
    return null;
  }
}

enum ConstellationCreateAction { request, post, person }

List<PopupMenuEntry<ConstellationCreateAction>> constellationCreateMenuItems(
  L10n l10n, {
  required bool phantomsEnabled,
  bool fromCanvas = false,
}) => [
  if (kPostsEnabled)
    PopupMenuItem(
      key: const Key('constellation.canvas.create_menu.post'),
      value: ConstellationCreateAction.post,
      child: Text(l10n.postCreateMenuPost),
    ),
  PopupMenuItem(
    key: const Key('constellation.canvas.create_menu.request'),
    value: ConstellationCreateAction.request,
    child: Text(l10n.postCreateMenuRequest),
  ),
  if (phantomsEnabled)
    PopupMenuItem(
      value: ConstellationCreateAction.person,
      child: Text(
        fromCanvas ? l10n.personCreateCanvasAction : l10n.personCreateAction,
      ),
    ),
];

Offset? _viewportCentre(ConstellationCubit cubit) {
  final controller = cubit.graphController;
  final size = controller.viewportSize;
  return size == null
      ? null
      : controller.viewportLocalToScene(size.center(Offset.zero));
}

Future<void> startConstellationCreate(
  BuildContext context, {
  required ConstellationCreateAction action,
  required ConstellationCubit cubit,
  required ConstellationComposerCubit composer,
  Offset? scenePosition,
}) async {
  final point = scenePosition ?? _viewportCentre(cubit);
  if (point == null) return;
  switch (action) {
    case ConstellationCreateAction.request:
      composer.start(BeaconKind.request, point);
    case ConstellationCreateAction.post:
      composer.start(BeaconKind.post, point);
    case ConstellationCreateAction.person:
      await showConstellationAddPerson(
        context,
        cubit: cubit,
        scenePosition: point,
      );
  }
}

Future<void> showConstellationAddPerson(
  BuildContext context, {
  required ConstellationCubit cubit,
  Offset? scenePosition,
}) async {
  final point = scenePosition ?? _viewportCentre(cubit);
  if (point == null) return;
  final position = constellationPointToV1Anchor((x: point.dx, y: point.dy));
  if (!ConstellationAnchorPosition.isFiniteV1Axis(position.xUnits) ||
      !ConstellationAnchorPosition.isFiniteV1Axis(position.yUnits)) {
    showSnackBar(context, text: L10n.of(context)!.personCreateOutsideField);
    return;
  }
  await showPhantomCreateSheet(context, position: position);
}

/// Opens the create menu at the pointer or beside its app-bar trigger.
Future<void> showConstellationCreateMenu(
  BuildContext context, {
  required ConstellationCubit cubit,
  required ConstellationComposerCubit composer,
  required Offset globalPosition,
  Offset? scenePosition,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) return;
  final action = await showMenu<ConstellationCreateAction>(
    context: context,
    position: RelativeRect.fromRect(
      overlay.globalToLocal(globalPosition) & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: constellationCreateMenuItems(
      L10n.of(context)!,
      phantomsEnabled: cubit.phantomsEnabled,
      fromCanvas: scenePosition != null,
    ),
    popUpAnimationStyle: AnimationStyle.noAnimation,
  );
  if (action != null && context.mounted) {
    await startConstellationCreate(
      context,
      action: action,
      cubit: cubit,
      composer: composer,
      scenePosition: scenePosition,
    );
  }
}
