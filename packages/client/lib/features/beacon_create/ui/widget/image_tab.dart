import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

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
        return ListView(
          padding: const EdgeInsets.all(kSpacingMedium),
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
              const SizedBox(height: kSpacingSmall),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: images.length,
                onReorder: cubit.reorderImages,
                itemBuilder: (context, index) {
                  final image = images[index];
                  return Card(
                    key: ObjectKey(image),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (image.imageBytes != null)
                          Image.memory(
                            image.imageBytes!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 200,
                          )
                        else if (image.id.isNotEmpty && image.authorId.isNotEmpty)
                          Image.network(
                            '$kImageServer/$kImagesPath/${image.authorId}/${image.id}.$kImageExt',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 200,
                            errorBuilder: (_, _, _) => const SizedBox(
                              height: 200,
                              child: Center(
                                child: Icon(Icons.photo_outlined, size: 64),
                              ),
                            ),
                          )
                        else
                          const SizedBox(
                            height: 200,
                            child: Center(
                              child: Icon(Icons.photo_outlined, size: 64),
                            ),
                          ),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: Theme.of(context).textTheme.labelMedium!
                                  .copyWith(
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
                            onPressed: () => cubit.removeImage(index),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: kSpacingLarge),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: cubit.pickImages,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const SizedBox(
                        height: 256,
                        child: Center(
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
  }
}
