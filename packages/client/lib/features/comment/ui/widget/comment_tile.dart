import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/comment.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/rating_indicator.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/like/ui/widget/like_control.dart';

class CommentTile extends StatelessWidget {
  const CommentTile({
    required this.comment,
    this.isMine = false,
    super.key,
  });

  final Comment comment;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Column(
      children: [
        const Divider(),

        Padding(
          key: const Key('CommentHeader'),
          padding: kPaddingSmallT,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              GestureDetector(
                onTap: isMine
                    ? null
                    : () => context.read<ScreenCubit>().showProfile(
                        comment.author.id,
                      ),
                child: Padding(
                  padding: const EdgeInsets.only(right: kSpacingMedium),
                  child: AvatarRated.small(profile: comment.author),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      isMine ? l10n.labelMe : comment.author.title,
                      style: theme.textTheme.headlineMedium,
                    ),

                    // Body
                    Padding(
                      padding: kPaddingSmallT,
                      child: ShowMoreText(
                        comment.content,
                        style: ShowMoreText.buildTextStyle(context),
                        colorClickableText: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // More
              PopupMenuButton(
                itemBuilder: (context) => <PopupMenuEntry<void>>[
                  // Complaint
                  PopupMenuItem(
                    onTap: () =>
                        context.read<ScreenCubit>().showComplaint(comment.id),
                    child: Text(l10n.buttonComplaint),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Buttons
        Padding(
          key: const Key('CommentButtons'),
          padding: kPaddingSmallV,
          child: Row(
            children: [
              // Share
              ShareCodeIconButton.id(comment.id),

              const Spacer(),

              // Rating bar
              if (!isMine) ...[
                Padding(
                  padding: kPaddingH,
                  child: RatingIndicator(
                    key: ValueKey(comment.score),
                    score: comment.score,
                  ),
                ),

                // Vote
                LikeControl(
                  key: ValueKey(comment),
                  entity: comment,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
