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
    return BlocSelector<BeaconCreateCubit, BeaconCreateState,
        List<ImageEntity>>(
      bloc: cubit,
      selector: (state) => state.images,
      builder: (context, images) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final tt = context.tt;
            final windowClass = windowClassForWidth(constraints.maxWidth);
            final useGrid = windowClass != WindowClass.compact;
            final crossAxisCount = windowClass == WindowClass.expanded ? 3 : 2;

            return ListView(
              padding: EdgeInsets.all(tt.screenHPadding),
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
                      icon: const Icon(Icons.delete_sweep, size: 20),
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
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(tt.cardRadius),
                          ),
                          child: AspectRatio(
                            aspectRatio: windowClass == WindowClass.expanded
                                ? 21 / 9
                                : 4 / 3,
                            child: const Center(
                              child: Icon(Icons.photo_outlined, size: 64),
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
              errorBuilder: (_, _, _) => const Center(
                child: Icon(Icons.photo_outlined, size: 64),
              ),
            )
          else
            const Center(
              child: Icon(Icons.photo_outlined, size: 64),
            ),
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelMedium!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
              ),
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}
