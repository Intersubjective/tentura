import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/beacon_create_cubit.dart';

class ImageTab extends StatelessWidget {
  const ImageTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<BeaconCreateCubit>();
    return BlocSelector<BeaconCreateCubit, BeaconCreateState, ImageEntity?>(
      bloc: cubit,
      selector: (state) => state.image,
      builder: (context, image) {
        const imagePadding = kSpacingLarge * 2;
        return ListView(
          children: [
            // Image Control
            if (image == null)
              ListTile(
                title: Text(L10n.of(context)!.attachImage),
                trailing: const Icon(Icons.add_a_photo_rounded),
                onTap: cubit.pickImage,
              )
            else
              ListTile(
                title: Text(image.fileName),
                trailing: IconButton(
                  icon: const Icon(Icons.cancel_rounded),
                  onPressed: cubit.clearImage,
                ),
              ),

            // Image Container
            Padding(
              padding: const EdgeInsets.only(
                top: kSpacingMedium,
                bottom: imagePadding,
                left: imagePadding,
                right: imagePadding,
              ),
              child: image?.imageBytes == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.black12,
                        ),
                      ),
                      child: const Icon(
                        Icons.photo_outlined,
                        size: 256,
                      ),
                    )
                  : Image.memory(
                      image!.imageBytes!,
                      key: ObjectKey(image),
                      fit: BoxFit.fitWidth,
                    ),
            ),
          ],
        );
      },
    );
  }
}
