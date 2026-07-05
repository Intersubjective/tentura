import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_requirements_bar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/tentura_info_hint_button.dart';

/// Thin metadata strip: avatar · author · needs · reach hint on one row.
class CompactBeaconContextStrip extends StatelessWidget {
  const CompactBeaconContextStrip({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  static const _tightStripMaxWidth = 400.0;

  static String _authorLabel(L10n l10n, Profile author, String viewerId) {
    final name = SelfUserHighlight.displayName(l10n, author, viewerId);
    if (name.isEmpty) {
      return l10n.noName;
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final start = beacon.startAt;
    final end = beacon.endAt;
    var dateRange = '';
    if (start != null || end != null) {
      final fmt = DateFormat.MMMd(locale);
      final a = start != null ? fmt.format(start.toLocal()) : '';
      final b = end != null ? fmt.format(end.toLocal()) : '';
      if (a.isNotEmpty && b.isNotEmpty) {
        dateRange = '$a—$b';
      } else {
        dateRange = a.isNotEmpty ? a : b;
      }
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.iconTextGap,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tt.borderSubtle),
        ),
      ),
      child: BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (p, c) => p.profile.id != c.profile.id,
        builder: (context, state) {
          final authorLine = _authorLabel(l10n, beacon.author, state.profile.id);
          final buffer = StringBuffer()..write(authorLine);
          if (kShowBeaconCardContextCategory) {
            final contextLabel = beacon.context.isNotEmpty
                ? beacon.context
                : l10n.inboxCategoryGeneral;
            buffer
              ..write(' · ')
              ..write(contextLabel);
          }
          if (dateRange.isNotEmpty) {
            buffer
              ..write(' · ')
              ..write(dateRange);
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final wc = windowClassForWidth(maxW);
              final tight = maxW < _tightStripMaxWidth;
              final needsMaxIcons = tight
                  ? 2
                  : (wc == WindowClass.compact ? 3 : 5);

              return Row(
                children: [
                  SelfAwareAvatar.small(
                    profile: beacon.author,
                  ),
                  SizedBox(width: tt.iconTextGap),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            buffer.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TenturaText.bodySmall(tt.textMuted),
                          ),
                        ),
                        if (beacon.needs.isNotEmpty) ...[
                          SizedBox(width: tt.iconTextGap),
                          Flexible(
                            child: BeaconRequirementsBar(
                              needs: beacon.needs,
                              inline: true,
                              maxIcons: needsMaxIcons,
                              leadingLabel: tight
                                  ? null
                                  : l10n.beaconForwardRequirementsHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  TenturaInfoHintButton(
                    fullText: l10n.forwardReachExplainer,
                    semanticsLabel: l10n.forwardReachExplainer,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
