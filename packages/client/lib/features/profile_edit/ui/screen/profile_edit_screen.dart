import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

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
                        // Remove Picture Button
                        ? IconButton.filledTonal(
                            iconSize: AvatarRated.sizeSmall,
                            icon: const Icon(Icons.highlight_remove_outlined),
                            onPressed: cubit.clearImage,
                          )
                        // Upload Picture Button
                        : IconButton.filledTonal(
                            iconSize: AvatarRated.sizeSmall,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            onPressed: cubit.pickImage,
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
