import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/help_path_node.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

/// Renders `(avatar) Name → …` for one canonical help path (closed Request row).
class HelpPathChainRow extends StatelessWidget {
  const HelpPathChainRow({
    required this.path,
    required this.onTap,
    super.key,
  });

  final List<HelpPathNode> path;
  final VoidCallback onTap;

  static const _avatarSize = kCoordinationLogAvatarSize;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return Semantics(
      button: true,
      label: helpPathAccessibilityLabel(
        title: l10n.closureHelpPathTitle,
        path: path,
        anonymousLabel: l10n.helpPathAnonymousCount,
      ),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tt.buttonRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _segments(context, path),
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: tt.textMuted,
                  size: tt.iconSize,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _segments(BuildContext context, List<HelpPathNode> path) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final children = <Widget>[];
    for (var i = 0; i < path.length; i++) {
      if (i != 0) {
        children.addAll([
          SizedBox(width: tt.tightGap),
          Icon(Icons.arrow_right_alt, size: _avatarSize, color: tt.textMuted),
          SizedBox(width: tt.tightGap),
        ]);
      }
      final node = path[i];
      if (node.isAnonymous) {
        children.add(
          Text(
            l10n.helpPathAnonymousCount(node.anonymousCount),
            style: TenturaText.bodySmall(tt.text),
          ),
        );
      } else {
        children.add(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TenturaAvatar(
                profile: Profile(
                  id: node.userId!,
                  displayName: node.displayName!,
                ),
                size: _avatarSize,
              ),
              SizedBox(width: tt.iconTextGap),
              Text(
                node.displayName!.trim(),
                style: TenturaText.bodySmall(tt.text),
              ),
            ],
          ),
        );
      }
    }
    return children;
  }
}

String helpPathAccessibilityLabel({
  required String title,
  required List<HelpPathNode> path,
  required String Function(int count) anonymousLabel,
}) {
  final parts = <String>[title];
  for (final node in path) {
    if (node.isAnonymous) {
      parts.add(anonymousLabel(node.anonymousCount));
    } else {
      parts.add(node.displayName!.trim());
    }
  }
  return parts.join(', ');
}
