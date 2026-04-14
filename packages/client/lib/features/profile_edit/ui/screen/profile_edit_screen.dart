import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:image_cropper/image_cropper.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/profile_edit_cubit.dart';

@RoutePage()
class ProfileEditScreen extends StatelessWidget
    with StringInputValidator
    implements AutoRouteWrapper {
  const ProfileEditScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ProfileEditCubit(
          profile: GetIt.I<ProfileCubit>().state.profile,
        ),
      ),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<ProfileEditCubit, ProfileEditState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final cubit = context.read<ProfileEditCubit>();
    final cropUiSettings = _avatarCropUiSettings(context, l10n);
    void pickAvatar() {
      unawaited(cubit.pickImage(cropUiSettings));
    }

    return Scaffold(
      // Header
      appBar: AppBar(
        actions: [
          // Save Button
          BlocSelector<ProfileEditCubit, ProfileEditState, bool>(
            selector: (state) => state.hasChanges,
            builder: (_, hasChanges) => TextButton(
              onPressed: hasChanges ? cubit.save : null,
              child: Text(l10n.buttonSave),
            ),
          ),
        ],
      ),
      resizeToAvoidBottomInset: false,

      // Form
      body: Column(
        children: [
          // Avatar
          BlocBuilder<ProfileEditCubit, ProfileEditState>(
            buildWhen: (p, c) =>
                p.image != c.image || p.willDropImage != c.willDropImage,
            builder: (_, state) {
              // Global [iconTheme] uses [ColorScheme.primary], same as
              // [secondaryContainer] on filled tonal buttons — icons would be
              // invisible without an explicit on-container foreground.
              final overlayIconStyle = IconButton.styleFrom(
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onSecondaryContainer,
                iconSize: 24,
              );
              return Stack(
                children: [
                  if (state.hasNoImage && state.canDropImage)
                    // Original Avatar
                    AvatarRated.big(
                      profile: cubit.state.original,
                      withRating: false,
                    )
                  else
                    SizedBox.square(
                      dimension: AvatarRated.sizeBig,
                      child: ClipOval(
                        child: state.hasNoImage || state.willDropImage
                            // Placeholder
                            ? AvatarRated.getAvatarPlaceholder()
                            // New Avatar
                            : Image.memory(
                                state.image!.imageBytes!,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),

                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: state.canDropImage
                        ? state.hasNoImage
                              // Current server avatar: change + remove
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton.filledTonal(
                                      style: overlayIconStyle,
                                      icon: const Icon(
                                        Icons.highlight_remove_outlined,
                                      ),
                                      onPressed: cubit.clearImage,
                                    ),
                                    IconButton.filledTonal(
                                      style: overlayIconStyle,
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: pickAvatar,
                                    ),
                                  ],
                                )
                              // New pick in memory: remove draft only
                              : IconButton.filledTonal(
                                  style: overlayIconStyle,
                                  icon: const Icon(
                                    Icons.highlight_remove_outlined,
                                  ),
                                  onPressed: cubit.clearImage,
                                )
                        // No avatar yet: pick first picture
                        : IconButton.filledTonal(
                            style: overlayIconStyle,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            onPressed: pickAvatar,
                          ),
                  ),
                ],
              );
            },
          ),

          // Username
          Padding(
            padding: kPaddingAll,
            child: TextFormField(
              autovalidateMode: AutovalidateMode.onUnfocus,
              decoration: InputDecoration(
                labelText: l10n.labelTitle,
                hintText: l10n.pleaseFillTitle,
              ),
              initialValue: cubit.state.title,
              maxLength: kTitleMaxLength,
              style: textTheme.headlineLarge,
              onChanged: cubit.setTitle,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              validator: (text) => titleValidator(l10n, text),
            ),
          ),

          // User Description
          Expanded(
            child: Padding(
              padding: kPaddingAll,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textStyle = textTheme.bodyMedium!;
                  final painter = TextPainter(
                    text: TextSpan(text: 'A', style: textStyle),
                    maxLines: 1,
                    textDirection: TextDirection.ltr,
                  )..layout();
                  return TextFormField(
                    maxLines: constraints.maxHeight > 0
                        ? (constraints.maxHeight / painter.height).floor()
                        : 1,
                    minLines: 1,
                    maxLength: kDescriptionMaxLength,
                    keyboardType: TextInputType.multiline,
                    initialValue: cubit.state.description,
                    autovalidateMode: AutovalidateMode.onUnfocus,
                    decoration: InputDecoration(
                      labelText: l10n.labelDescription,
                      labelStyle: textTheme.bodyMedium,
                    ),
                    style: textStyle,
                    onChanged: cubit.setDescription,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    validator: (text) => descriptionValidator(l10n, text),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Web cropper area: fits viewport so the default dialog layout does not overflow.
int _avatarCropperWebSide(BuildContext context) {
  final mq = MediaQuery.sizeOf(context);
  const padding = 24.0;
  final topChrome = MediaQuery.paddingOf(context).top + kToolbarHeight;
  const bottomChrome = 140.0;
  final bottom = MediaQuery.paddingOf(context).bottom + bottomChrome;
  final maxByHeight = (mq.height - topChrome - bottom).floor();
  final maxByWidth = (mq.width - 2 * padding).floor();
  return min(maxByHeight, maxByWidth).clamp(200, 500);
}

List<PlatformUiSettings> _avatarCropUiSettings(
  BuildContext context,
  L10n l10n,
) {
  final webSide = _avatarCropperWebSide(context);
  return [
    AndroidUiSettings(
      toolbarTitle: l10n.titleCropAvatar,
      cropStyle: CropStyle.circle,
      lockAspectRatio: true,
      initAspectRatio: CropAspectRatioPreset.square,
      aspectRatioPresets: const [CropAspectRatioPreset.square],
    ),
    IOSUiSettings(
      title: l10n.titleCropAvatar,
      cropStyle: CropStyle.circle,
      aspectRatioLockEnabled: true,
      aspectRatioPickerButtonHidden: true,
      resetAspectRatioEnabled: false,
      aspectRatioPresets: const [CropAspectRatioPreset.square],
    ),
    WebUiSettings(
      context: context,
      presentStyle: WebPresentStyle.page,
      size: CropperSize(width: webSide, height: webSide),
      viewwMode: WebViewMode.mode_1,
      translations: WebTranslations(
        title: l10n.titleCropAvatar,
        rotateLeftTooltip: l10n.cropRotateLeftTooltip,
        rotateRightTooltip: l10n.cropRotateRightTooltip,
        cancelButton: l10n.buttonCancel,
        cropButton: l10n.buttonCrop,
      ),
    ),
  ];
}
