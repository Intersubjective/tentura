import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/dialog/error_dialog.dart';
import 'package:tentura/ui/widget/avatar_image.dart';
import 'package:tentura/ui/widget/gradient_stack.dart';
import 'package:tentura/ui/widget/avatar_positioned.dart';

import '../bloc/profile_cubit.dart';

@RoutePage()
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _profileCubit = context.read<ProfileCubit>();
  late final _profile = _profileCubit.state.user;

  late final _nameController = TextEditingController(
    text: _profile.title,
  );
  late final _descriptionController = TextEditingController(
    text: _profile.description,
  );

  late bool _hasPicture = _profile.has_picture;

  Uint8List? _imageBytes;

  @override
  void dispose() {
    _descriptionController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          // Save Button
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton.outlined(
              icon: const Icon(Icons.save),
              onPressed: _onSavePressed,
            ),
          ),
        ],
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          // Header
          GradientStack(
            children: [
              // Avatar
              AvatarPositioned(
                child: _imageBytes == null
                    ? AvatarImage(
                        size: AvatarPositioned.childSize,
                        userId: _hasPicture ? _profile.imageId : '',
                      )
                    : Container(
                        clipBehavior: Clip.hardEdge,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                        ),
                        child: Image.memory(
                          _imageBytes!,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),

              // Upload\Remove Picture Button
              Positioned(
                top: 225,
                left: 200,
                child: _hasPicture
                    ? IconButton.filledTonal(
                        iconSize: 50,
                        icon: const Icon(Icons.highlight_remove_outlined),
                        onPressed: () => setState(() {
                          _hasPicture = false;
                          _imageBytes = null;
                        }),
                      )
                    : IconButton.filledTonal(
                        iconSize: 50,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        onPressed: () async {
                          final image = await _profileCubit.pickImage();
                          if (image != null) {
                            setState(() {
                              _hasPicture = true;
                              _imageBytes = image.bytes;
                            });
                          }
                        },
                      ),
              ),
            ],
          ),

          // Username
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 20,
            ),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: TextFormField(
                maxLength: titleMaxLength,
                controller: _nameController,
                style: textTheme.headlineLarge,
                decoration: const InputDecoration(
                  labelText: 'Name',
                ),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                validator: (value) {
                  if (value == null || value.length < titleMinLength) {
                    return 'Have to be at least 3 char long!';
                  }
                  return null;
                },
              ),
            ),
          ),

          // User Description
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 20,
            ),
            child: TextFormField(
              minLines: 1,
              maxLines: 20,
              style: textTheme.bodyLarge,
              maxLength: descriptionLength,
              controller: _descriptionController,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Description',
              ),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSavePressed() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      if (_imageBytes != null) {
        await _profileCubit.putAvatarImage(_imageBytes!);
        await CachedNetworkImage.evictFromCache(
          AvatarImage.getAvatarUrl(userId: _profile.id),
        );
      }
      await _profileCubit.update(
        title: _nameController.text,
        description: _descriptionController.text,
        hasPicture: _hasPicture,
      );
      if (mounted) await context.maybePop();
    } catch (e) {
      if (mounted) {
        await showAdaptiveDialog<void>(
          context: context,
          builder: (_) => ErrorDialog(error: e),
        );
      }
    }
  }
}
