import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_create_cubit.dart';
import 'cover_crop_ui.dart';

class ImageTab extends StatelessWidget {
  const ImageTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BeaconCreateCubit>();
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    return BlocSelector<
      BeaconCreateCubit,
      BeaconCreateState,
      ({List<ImageEntity> images, String? coverKey, ImageEntity? coverThumb})
    >(
      bloc: cubit,
      selector: (state) => (
        images: state.images,
        coverKey: state.coverKey,
        coverThumb: state.coverThumb,
      ),
      builder: (context, media) {
        final images = media.images;
        return LayoutBuilder(
          builder: (context, constraints) {
            final windowClass = windowClassForWidth(constraints.maxWidth);
            final useGrid = windowClass != WindowClass.compact;
            final crossAxisCount = windowClass == WindowClass.expanded ? 3 : 2;

            // Single scroll owner; nested ListView/GridView caused
            // parentDataDirty semantics asserts on web.
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: ListTile(
                    title: Text(L10n.of(context)!.attachImage),
                    trailing: const Icon(Icons.add_a_photo_rounded),
                    onTap: cubit.pickImages,
                  ),
                ),
                if (images.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: cubit.clearAllImages,
                        icon: Icon(Icons.delete_sweep, size: tt.iconSize),
                        label: Text(L10n.of(context)!.removeAll),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: tt.rowGap / 2)),
                  if (useGrid)
                    SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: tt.cardGap,
                        mainAxisSpacing: tt.rowGap,
                        childAspectRatio: 4 / 3,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _imageCard(
                          cubit: cubit,
                          image: images[index],
                          index: index,
                          coverKey: media.coverKey,
                          coverThumb: media.coverThumb,
                        ),
                        childCount: images.length,
                      ),
                    )
                  else
                    SliverReorderableList(
                      itemCount: images.length,
                      onReorderItem: cubit.reorderImages,
                      itemBuilder: (context, index) =>
                          ReorderableDelayedDragStartListener(
                            // Identity, not position: reordering must not
                            // rebuild a card as if it were a different image.
                            key: ValueKey(images[index].key),
                            index: index,
                            child: _imageCard(
                              cubit: cubit,
                              image: images[index],
                              index: index,
                              coverKey: media.coverKey,
                              coverThumb: media.coverThumb,
                            ),
                          ),
                    ),
                ] else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: tt.rowGap * 2),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(tt.cardRadius),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: cubit.pickImages,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: scheme.outlineVariant),
                              borderRadius: BorderRadius.circular(
                                tt.cardRadius,
                              ),
                            ),
                            child: AspectRatio(
                              aspectRatio: windowClass == WindowClass.expanded
                                  ? 21 / 9
                                  : 4 / 3,
                              child: Center(
                                child: Icon(
                                  Icons.photo_outlined,
                                  size: tt.iconSize * 3,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _imageCard({
    required BeaconCreateCubit cubit,
    required ImageEntity image,
    required int index,
    required String? coverKey,
    required ImageEntity? coverThumb,
  }) => _ImageCard(
    image: image,
    index: index,
    isCover: coverKey == image.key,
    hasCoverThumb: coverKey == image.key && coverThumb != null,
    onRemove: () => cubit.removeImage(index),
    onUseAsCover: () => cubit.setCoverImageKey(image.key),
    onAdjustCover: (context) => unawaited(
      cubit.adjustCoverCrop(
        BeaconCoverCropUi(context, L10n.of(context)!),
      ),
    ),
    onResetCoverThumb: cubit.clearCoverThumb,
  );
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.image,
    required this.index,
    required this.isCover,
    required this.hasCoverThumb,
    required this.onRemove,
    required this.onUseAsCover,
    required this.onAdjustCover,
    required this.onResetCoverThumb,
  });

  final ImageEntity image;
  final int index;
  final bool isCover;
  final bool hasCoverThumb;
  final VoidCallback onRemove;
  final VoidCallback onUseAsCover;
  final void Function(BuildContext context) onAdjustCover;
  final VoidCallback onResetCoverThumb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image.imageBytes != null)
              Image.memory(
                image.imageBytes!,
                fit: BoxFit.cover,
              )
            else if (image.id.isNotEmpty && image.authorId.isNotEmpty)
              Image.network(
                '$kImageServer/$kImagesPath/${image.authorId}/${image.id}.$kImageExt',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Icon(
                    Icons.photo_outlined,
                    size: tt.iconSize * 3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Center(
                child: Icon(
                  Icons.photo_outlined,
                  size: tt.iconSize * 3,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            Positioned(
              top: tt.tightGap,
              left: tt.tightGap,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.scrim.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(tt.buttonRadius),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tt.tightGap * 2,
                    vertical: tt.tightGap,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelMedium!.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: tt.tightGap,
              right: tt.tightGap,
              child: IconButton.filled(
                key: Key('BeaconImage.Remove.${image.key}'),
                style: IconButton.styleFrom(
                  backgroundColor: scheme.scrim.withValues(alpha: 0.55),
                  foregroundColor: scheme.onPrimary,
                ),
                icon: Icon(Icons.close, size: tt.iconSize),
                onPressed: onRemove,
              ),
            ),
            Positioned(
              left: tt.tightGap,
              right: tt.tightGap,
              bottom: tt.tightGap,
              child: isCover
                  ? _coverBadge(context, l10n)
                  : Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _pill(
                        context,
                        child: TextButton.icon(
                          key: Key('BeaconImage.UseAsCover.${image.key}'),
                          onPressed: onUseAsCover,
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.onPrimary,
                          ),
                          icon: Icon(
                            Icons.image_outlined,
                            size: tt.iconSize,
                          ),
                          label: Text(l10n.beaconCoverUseAsCover),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cover marking carries a check glyph and a semantic label, so it never
  /// depends on colour alone.
  Widget _coverBadge(BuildContext context, L10n l10n) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    return Row(
      children: [
        _pill(
          context,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.tightGap * 2,
              vertical: tt.tightGap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: tt.iconSize,
                  color: scheme.onPrimary,
                ),
                SizedBox(width: tt.iconTextGap),
                Text(
                  l10n.beaconCoverSelected,
                  style: TenturaText.labelMedium(scheme.onPrimary),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (hasCoverThumb)
          _pill(
            context,
            child: IconButton(
              key: Key('BeaconImage.ResetCoverThumb.${image.key}'),
              tooltip: l10n.beaconCoverThumbReset,
              color: scheme.onPrimary,
              icon: Icon(Icons.restart_alt_rounded, size: tt.iconSize),
              onPressed: onResetCoverThumb,
            ),
          ),
        if (hasCoverThumb) SizedBox(width: tt.tightGap),
        _pill(
          context,
          child: IconButton(
            key: Key('BeaconImage.AdjustCover.${image.key}'),
            tooltip: l10n.beaconCoverAdjust,
            color: scheme.onPrimary,
            icon: Icon(Icons.crop_rounded, size: tt.iconSize),
            onPressed: () => onAdjustCover(context),
          ),
        ),
      ],
    );
  }

  Widget _pill(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.scrim.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(tt.buttonRadius),
      ),
      child: child,
    );
  }
}
