import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/opinion.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../bloc/opinion_cubit.dart';
import '../dialog/opinion_delete_dialog.dart';

class OpinionTile extends StatelessWidget {
  const OpinionTile({
    required this.opinion,
    this.isMine = false,
    super.key,
  });

  final Opinion opinion;

  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final screenCubit = context.read<ScreenCubit>();
    return Column(
      children: [
        // Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            GestureDetector(
              onTap: isMine
                  ? null
                  : () => screenCubit.showProfile(opinion.author.id),
              child: Padding(
                padding: const EdgeInsets.only(right: kSpacingMedium),
                child: AvatarRated.small(
                  profile: opinion.author,
                  withRating: !isMine,
                ),
              ),
            ),

            // Body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  if (isMine)
                    Text(
                      l10n.labelMe,
                      style: theme.textTheme.headlineMedium,
                    )
                  else
                    GestureDetector(
                      onTap: () => screenCubit.showProfile(opinion.author.id),
                      child: Text(
                        opinion.author.title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),

                  // Opinion
                  Padding(
                    padding: kPaddingSmallT,
                    child: ShowMoreText(
                      opinion.content,
                      style: ShowMoreText.buildTextStyle(context),
                      colorClickableText: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // More
            PopupMenuButton(
              itemBuilder: (context) => [
                if (isMine)
                  PopupMenuItem<void>(
                    onTap: () async {
                      final opinionCubit = context.read<OpinionCubit>();
                      if (await OpinionDeleteDialog.show(context) ?? false) {
                        await opinionCubit.removeOpinionById(opinion.id);
                      }
                    },
                    child: Text(l10n.deleteOpinion),
                  )
                else
                  // Complaint
                  PopupMenuItem<void>(
                    onTap: () => screenCubit.showComplaint(opinion.id),
                    child: Text(l10n.buttonComplaint),
                  ),
              ],
            ),
          ],
        ),

        // Footer (Buttons)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Share
            ShareCodeIconButton.id(opinion.id),

            // Status
            Padding(
              padding: kPaddingH,
              child: opinion.amount > 0
                  ? Icon(
                      Icons.sentiment_satisfied_outlined,
                      color: Colors.green.shade300,
                    )
                  : Icon(
                      Icons.sentiment_dissatisfied_outlined,
                      color: Colors.red.shade300,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
