import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_last_event.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_activity_event_presenter.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

const _kMyWorkLastEventAvatarSize = 18.0;

/// Last meaningful beacon event on My Work cards (icon + label + actor + ago).
class MyWorkLastEventRow extends StatefulWidget {
  const MyWorkLastEventRow({
    required this.beacon,
    required this.viewModel,
    required this.currentUserId,
    super.key,
  });

  final Beacon beacon;
  final MyWorkCardViewModel viewModel;
  final String currentUserId;

  @override
  State<MyWorkLastEventRow> createState() => _MyWorkLastEventRowState();
}

class _MyWorkLastEventRowState extends State<MyWorkLastEventRow> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final last = widget.viewModel.lastActivityEvent;

    if (last == null) {
      if (!beaconHasRealUpdate(widget.beacon)) {
        return const SizedBox.shrink();
      }
      final ago = compactRelativeTimeAgo(
        when: widget.beacon.updatedAt,
        now: now,
        l10n: l10n,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: BeaconHudIconRow(
          leadIcon: BeaconHudRowIcons.lastEvent,
          semanticsLabel: l10n.beaconHudLastEventRowSemantics,
          leadAlign: BeaconHudRowLeadAlign.center,
          body: Text(
            l10n.myWorkUpdatedRelative(ago),
            style: beaconCardUpdatedLineTextStyle(theme),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return _EventLine(
      l10n: l10n,
      theme: theme,
      scheme: scheme,
      beacon: widget.beacon,
      last: last,
      currentUserId: widget.currentUserId,
      now: now,
    );
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine({
    required this.l10n,
    required this.theme,
    required this.scheme,
    required this.beacon,
    required this.last,
    required this.currentUserId,
    required this.now,
  });

  final L10n l10n;
  final ThemeData theme;
  final ColorScheme scheme;
  final Beacon beacon;
  final MyWorkLastEvent last;
  final String currentUserId;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final event = last.event;
    final label = beaconActivityEventLabel(l10n, event);
    final ago = compactRelativeTimeAgo(
      when: event.createdAt,
      now: now,
      l10n: l10n,
    );
    final actor = last.actor;
    final isYou = actor.id.isNotEmpty && actor.id == currentUserId;
    final isAuthor = actor.id.isNotEmpty && actor.id == beacon.author.id;
    final actorLabel = _actorShortName(l10n, actor, isYou: isYou);
    final semanticsLabel = l10n.myWorkLastEventSemantics(
      label,
      actorLabel,
      ago,
      isAuthor ? l10n.myWorkLastEventAuthorSuffix : '',
    );

    final bodyStyle = theme.textTheme.bodySmall!.copyWith(
      height: 1.15,
      color: scheme.onSurfaceVariant,
    );
    final agoStyle = theme.textTheme.bodySmall!.copyWith(
      height: 1.15,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
    );
    final youStyle = bodyStyle.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w500,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Semantics(
        label: semanticsLabel,
        child: BeaconHudIconRow(
          leadIcon: BeaconHudRowIcons.lastEvent,
          semanticsLabel: l10n.beaconHudLastEventRowSemantics,
          leadAlign: BeaconHudRowLeadAlign.center,
          body: Text.rich(
            TextSpan(
              style: bodyStyle,
              children: [
                TextSpan(text: label),
                TextSpan(
                  text: ' ${l10n.myWorkLastEventBy} ',
                  style: bodyStyle.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ),
                if (!isYou)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ExcludeSemantics(
                        child: TenturaAvatar.tiny(
                          profile: actor,
                          size: _kMyWorkLastEventAvatarSize,
                          showAuthorStar: isAuthor,
                        ),
                      ),
                    ),
                  ),
                TextSpan(
                  text: actorLabel,
                  style: isYou ? youStyle : bodyStyle,
                ),
                TextSpan(
                  text: ', $ago',
                  style: agoStyle,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

String _actorShortName(L10n l10n, Profile actor, {required bool isYou}) {
  if (isYou) {
    return l10n.myWorkLastEventYou;
  }
  final name = actor.shownName.trim();
  if (name.isEmpty) {
    return '';
  }
  return name.split(RegExp(r'\s+')).first;
}
