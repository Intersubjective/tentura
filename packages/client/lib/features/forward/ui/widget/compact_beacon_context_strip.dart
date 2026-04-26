import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/self_aware_plain_mini_avatar.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

/// Thin metadata strip: `author · context · start—end` (hidden while search focused).
class CompactBeaconContextStrip extends StatelessWidget {
  const CompactBeaconContextStrip({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

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

    final contextLabel = beacon.context.isNotEmpty
        ? beacon.context
        : l10n.inboxCategoryGeneral;

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
        vertical: 6,
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
          final buffer = StringBuffer()
            ..write(authorLine)
            ..write(' · ')
            ..write(contextLabel);
          if (dateRange.isNotEmpty) {
            buffer
              ..write(' · ')
              ..write(dateRange);
          }
          return Row(
            children: [
              SelfAwarePlainMiniAvatar(
                profile: beacon.author,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  buffer.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
