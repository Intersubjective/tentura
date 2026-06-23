import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/beacon_create_cubit.dart';

class ImageTab extends StatelessWidget {
  const ImageTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BeaconCreateCubit>();
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    return BlocSelector<BeaconCreateCubit, BeaconCreateState,
        List<ImageEntity>>(
      bloc: cubit,
      selector: (state) => state.images,
      builder: (context, images) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final windowClass = windowClassForWidth(constraints.maxWidth);
            final useGrid = windowClass != WindowClass.compact;
            final crossAxisCount = windowClass == WindowClass.expanded ? 3 : 2;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  title: Text(L10n.of(context)!.attachImage),
                  trailing: const Icon(Icons.add_a_photo_rounded),
                  onTap: cubit.pickImages,
                ),
                if (images.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: cubit.clearAllImages,
                      icon: Icon(Icons.delete_sweep, size: tt.iconSize),
                      label: Text(L10n.of(context)!.removeAll),
                    ),
                  ),
                  SizedBox(height: tt.rowGap / 2),
                  if (useGrid)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: tt.cardGap,
                        mainAxisSpacing: tt.rowGap,
                        childAspectRatio: 4 / 3,
                      ),
                      itemCount: images.length,
                      itemBuilder: (context, index) => _ImageCard(
                        image: images[index],
                        index: index,
                        onRemove: () => cubit.removeImage(index),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: images.length,
                      onReorder: cubit.reorderImages,
                      itemBuilder: (context, index) => _ImageCard(
                        key: ObjectKey(images[index]),
                        image: images[index],
                        index: index,
                        onRemove: () => cubit.removeImage(index),
                      ),
                    ),
                ] else
                  Padding(
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
                            borderRadius: BorderRadius.circular(tt.cardRadius),
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
              ],
            );
          },
        );
      },
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.image,
    required this.index,
    required this.onRemove,
    super.key,
  });

  final ImageEntity image;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    return Card(
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
              style: IconButton.styleFrom(
                backgroundColor: scheme.scrim.withValues(alpha: 0.55),
                foregroundColor: scheme.onPrimary,
              ),
              icon: Icon(Icons.close, size: tt.iconSize),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}
