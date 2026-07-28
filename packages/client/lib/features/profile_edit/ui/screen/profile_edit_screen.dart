import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:auto_route/auto_route.dart';
import 'package:image_cropper/image_cropper.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/profile_edit_cubit.dart';

@RoutePage()
class ProfileEditScreen extends StatefulWidget implements AutoRouteWrapper {
  const ProfileEditScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ProfileEditCubit(
      profile: GetIt.I<ProfileCubit>().state.profile,
    ),
    child: this,
  );

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen>
    with StringInputValidator {
  final _formKey = GlobalKey<FormState>();

  void _save(ProfileEditCubit cubit) {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    unawaited(cubit.save());
  }

  Future<void> _requestClose(BuildContext context, {required bool isDirty}) {
    return TenturaSheetDismissGuard.requestClose(
      context,
      isDirty: isDirty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final tt = context.tt;
    final fieldPadding = EdgeInsets.all(tt.screenHPadding);
    final cubit = context.read<ProfileEditCubit>();
    final cropUiSettings = _avatarCropUiSettings(context, l10n);
    void uploadAvatar() {
      unawaited(cubit.uploadImage(cropUiSettings));
    }

    void cropAvatar() {
      unawaited(cubit.cropCurrentImage(cropUiSettings));
    }

    return BlocSelector<ProfileEditCubit, ProfileEditState, bool>(
      selector: (state) => state.hasChanges,
      builder: (context, hasChanges) {
        return PopScope(
          canPop: !hasChanges,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            await _requestClose(context, isDirty: hasChanges);
          },
          child: Form(
            key: _formKey,
            child: Scaffold(
              appBar: TenturaTopBar.of(
                context,
                title: Text(l10n.profileOverflowEdit),
                leading: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () =>
                      unawaited(_requestClose(context, isDirty: hasChanges)),
                ),
                actions: [
                  BlocSelector<ProfileEditCubit, ProfileEditState, (bool, bool)>(
                    selector: (state) => (state.hasChanges, state.isLoading),
                    builder: (_, state) {
                      final (hasChanges, isLoading) = state;
                      return TextButton(
                        onPressed: hasChanges && !isLoading
                            ? () => _save(cubit)
                            : null,
                        child: Text(l10n.buttonSave),
                      );
                    },
                  ),
                ],
                progress: BlocSelector<ProfileEditCubit, ProfileEditState, bool>(
                  selector: (state) => state.isLoading,
                  builder: TenturaTopBar.loadingBar,
                ),
              ),
              resizeToAvoidBottomInset: false,
              body: SafeArea(
                child: TenturaContentColumn(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          tt.screenHPadding,
                          tt.sectionGap,
                          tt.screenHPadding,
                          tt.rowGap,
                        ),
                        child: BlocBuilder<ProfileEditCubit, ProfileEditState>(
                          buildWhen: (p, c) =>
                              p.image != c.image ||
                              p.willDropImage != c.willDropImage ||
                              p.isLoading != c.isLoading,
                          builder: (_, state) {
                            final avatarSize =
                                tt.avatarSize *
                                (kTenturaAvatarBigSize /
                                    kTenturaAvatarDefaultMedium);
                            return Column(
                              children: [
                                if (state.hasNoImage && state.canDropImage)
                                  SelfAwareAvatar.big(
                                    profile: cubit.state.original,
                                  )
                                else
                                  SizedBox.square(
                                    dimension: avatarSize,
                                    child: ClipOval(
                                      child:
                                          state.hasNoImage || state.willDropImage
                                          ? TenturaAvatar.avatarPlaceholder()
                                          : Image.memory(
                                              state.image!.imageBytes!,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                SizedBox(height: tt.rowGap),
                                _ProfileAvatarActions(
                                  canRemove:
                                      state.canDropImage || state.hasImage,
                                  canCrop:
                                      state.hasImage ||
                                      (state.canDropImage &&
                                          state.hasNoImage &&
                                          cubit.state.original.hasAvatar),
                                  isLoading: state.isLoading,
                                  onRemove: cubit.clearImage,
                                  onCrop: cropAvatar,
                                  onUpload: uploadAvatar,
                                  uploadLabel: l10n.titleUploadProfilePhoto,
                                  cropLabel: l10n.titleCropAvatar,
                                  removeLabel: l10n.buttonRemove,
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      Padding(
                        padding: fieldPadding,
                        child: TextFormField(
                          autovalidateMode: AutovalidateMode.onUnfocus,
                          decoration: InputDecoration(
                            labelText: l10n.labelDisplayName,
                            hintText: l10n.pleaseFillDisplayName,
                          ),
                          initialValue: cubit.state.displayName,
                          maxLength: kTitleMaxLength,
                          style: textTheme.headlineLarge,
                          onChanged: cubit.setDisplayName,
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          validator: (text) => displayNameValidator(l10n, text),
                        ),
                      ),

                      Padding(
                        padding: fieldPadding,
                        child: TextFormField(
                          autovalidateMode: AutovalidateMode.onUnfocus,
                          decoration: InputDecoration(
                            labelText: l10n.labelUserHandle,
                            hintText: l10n.userHandleHint,
                            helperText: l10n.userHandleHelper,
                          ),
                          initialValue: cubit.state.handle,
                          maxLength: kUserHandleMaxLength,
                          keyboardType: TextInputType.text,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp('[a-z0-9_]'),
                            ),
                          ],
                          style: textTheme.bodyLarge,
                          onChanged: cubit.setHandle,
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          validator: (text) {
                            final t = (text ?? '').trim().toLowerCase();
                            if (t.isEmpty) return null;
                            if (!isValidUserHandleFormat(t)) {
                              return l10n.userHandleInvalidFormat;
                            }
                            return null;
                          },
                        ),
                      ),

                      Expanded(
                        child: Padding(
                          padding: fieldPadding,
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
                                    ? (constraints.maxHeight / painter.height)
                                          .floor()
                                    : 1,
                                minLines: 1,
                                maxLength: kDescriptionMaxLength,
                                keyboardType: TextInputType.multiline,
                                initialValue: cubit.state.description,
                                autovalidateMode: AutovalidateMode.onUnfocus,
                                decoration: InputDecoration(
                                  labelText: l10n.labelDescription,
                                  labelStyle: textTheme.bodyMedium,
                                  helperText: l10n.profileDescriptionHelper,
                                ),
                                style: textStyle,
                                onChanged: cubit.setDescription,
                                onTapOutside: (_) =>
                                    FocusScope.of(context).unfocus(),
                                validator: (text) =>
                                    descriptionValidator(l10n, text),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileAvatarActions extends StatelessWidget {
  const _ProfileAvatarActions({
    required this.canRemove,
    required this.canCrop,
    required this.isLoading,
    required this.onRemove,
    required this.onCrop,
    required this.onUpload,
    required this.uploadLabel,
    required this.cropLabel,
    required this.removeLabel,
  });

  final bool canRemove;
  final bool canCrop;
  final bool isLoading;
  final VoidCallback onRemove;
  final VoidCallback onCrop;
  final VoidCallback onUpload;
  final String uploadLabel;
  final String cropLabel;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final children = <Widget>[
      OutlinedButton(
        onPressed: isLoading ? null : onUpload,
        child: Text(uploadLabel),
      ),
      if (canCrop)
        OutlinedButton(
          onPressed: isLoading ? null : onCrop,
          child: Text(cropLabel),
        ),
      if (canRemove)
        OutlinedButton(
          onPressed: isLoading ? null : onRemove,
          child: Text(removeLabel),
        ),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: tt.tightGap,
      runSpacing: tt.tightGap,
      children: children,
    );
  }
}

/// Web cropper area: fits viewport so the default dialog layout does not overflow.
int _avatarCropperWebSide(BuildContext context) {
  final mq = MediaQuery.sizeOf(context);
  const padding = 24.0;
  final topChrome = MediaQuery.paddingOf(context).top + kToolbarHeight;
  const bottomChrome = 220.0;
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
      dragMode: WebDragMode.move,
      checkCrossOrigin: false,
      translations: WebTranslations(
        title: l10n.titleCropAvatar,
        rotateLeftTooltip: l10n.cropRotateLeftTooltip,
        rotateRightTooltip: l10n.cropRotateRightTooltip,
        cancelButton: l10n.buttonCancel,
        cropButton: l10n.buttonSaveAvatar,
      ),
    ),
  ];
}
