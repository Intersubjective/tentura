import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Overlapping mini-avatars with circular `+N` overflow (inbox forwarders style).
///
/// Facepile layout: overlap grows right (LTR). Stack paint order (back → front):
/// rightmost face, …, leftmost face (primary slot foremost), self slot above
/// other profiles, then `+N` on top.
class OverlappingPeopleAvatars extends StatelessWidget {
  const OverlappingPeopleAvatars({
    required this.profiles,
    this.overflowCount = 0,
    this.sizeBucket = TenturaAvatarSize.small,
    this.size,
    this.overlap = 6,
    this.starredProfileId,
    this.selfUserId,
    this.overflowBadgeFillColor,
    this.overflowBadgeTextColor,
    this.overflowRingColor,
    this.semanticsLabel,
    this.showPresence = false,
    super.key,
  });

  final List<Profile> profiles;
  final int overflowCount;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final double overlap;

  /// When set, the matching profile slot shows an author star badge.
  final String? starredProfileId;

  /// When set, the matching profile slot shows the self halo.
  final String? selfUserId;

  final Color? overflowBadgeFillColor;
  final Color? overflowBadgeTextColor;
  final Color? overflowRingColor;
  final String? semanticsLabel;

  /// Live online dot per face from [PresenceCubit] (when one is provided),
  /// the same dot as on chat avatars (U093).
  final bool showPresence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ringColor = overflowRingColor ?? scheme.outlineVariant;
    final badgeFill = overflowBadgeFillColor ?? scheme.surfaceContainerHigh;
    final badgeFg = overflowBadgeTextColor ?? scheme.onSurfaceVariant;
    final avatarSize = size ?? TenturaAvatar.resolveSize(context, sizeBucket);

    final extraSlots = overflowCount > 0 ? 1 : 0;
    final n = profiles.length + extraSlots;
    if (n == 0) {
      return const SizedBox.shrink();
    }

    final step = avatarSize - overlap;
    final width = avatarSize + (n - 1) * step;
    final theme = Theme.of(context);
    final label =
        semanticsLabel ??
        _defaultSemanticsLabel(
          profiles.length,
          overflowCount,
        );

    // One lookup per pile, not per face; previews and tests may build the
    // pile without presence data.
    final presence = showPresence ? _presenceOf(context) : null;

    final selfIndex = selfUserId == null
        ? -1
        : profiles.indexWhere((p) => p.id == selfUserId);

    final stackChildren = <Widget>[
      for (var i = profiles.length - 1; i >= 0; i--)
        if (i != selfIndex)
          Positioned(
            left: i * step,
            child: _PeopleAvatarSlot(
              profile: profiles[i],
              sizeBucket: sizeBucket,
              size: size,
              showStar:
                  starredProfileId != null &&
                  profiles[i].id == starredProfileId,
              isSelf: false,
            ),
          ),
      if (selfIndex >= 0)
        Positioned(
          left: selfIndex * step,
          child: _PeopleAvatarSlot(
            profile: profiles[selfIndex],
            sizeBucket: sizeBucket,
            size: size,
            showStar:
                starredProfileId != null &&
                profiles[selfIndex].id == starredProfileId,
            isSelf: true,
          ),
        ),
      if (overflowCount > 0)
        Positioned(
          left: profiles.length * step,
          child: Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: badgeFill,
              border: Border.all(color: ringColor),
            ),
            alignment: Alignment.center,
            child: Text(
              '+$overflowCount',
              style: theme.textTheme.labelMedium!.copyWith(
                fontWeight: FontWeight.w700,
                color: badgeFg,
                height: 1,
              ),
            ),
          ),
        ),
      // Online dots go on a top layer, after every face: inside a slot the
      // face's own ring and the next slot painted over it, so the dot read
      // as a slashed glyph (#533).
      if (presence != null)
        for (var i = 0; i < profiles.length; i++)
          Positioned(
            left: i * step + avatarSize - avatarSize * _dotFraction,
            top: avatarSize - avatarSize * _dotFraction,
            child: _PresenceDotSlot(
              userId: profiles[i].id,
              size: avatarSize * _dotFraction,
              presence: presence,
            ),
          ),
    ];

    final pile = SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: stackChildren,
      ),
    );
    Widget labelled(String text) => Semantics(
      container: true,
      label: text,
      // Avatars/Text still publish semantics; keep a single merged node on web.
      child: ExcludeSemantics(child: pile),
    );
    if (presence == null) return labelled(label);
    // The dot is colour only: say "N online" too (U093 review).
    return BlocSelector<PresenceCubit, Map<String, UserPresenceStatus>, int>(
      bloc: presence,
      selector: (state) => onlineCount(state, profiles),
      builder: (context, online) {
        final onlineText = online == 0
            ? null
            : L10n.of(context)?.facepileOnlineCount(online);
        return labelled(onlineText == null ? label : '$label, $onlineText');
      },
    );
  }

  /// Same share of the face as the dot on a single [TenturaAvatar].
  static const _dotFraction = 0.28;

  /// How many of [profiles] [state] reports online.
  static int onlineCount(
    Map<String, UserPresenceStatus> state,
    Iterable<Profile> profiles,
  ) => profiles.where((p) => state[p.id] == UserPresenceStatus.online).length;

  static PresenceCubit? _presenceOf(BuildContext context) {
    try {
      return context.read<PresenceCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  static String _defaultSemanticsLabel(int visibleCount, int overflowCount) {
    final people = visibleCount == 1 ? '1 person' : '$visibleCount people';
    if (overflowCount <= 0) {
      return people;
    }
    return '$people, $overflowCount more';
  }
}

class _PeopleAvatarSlot extends StatelessWidget {
  const _PeopleAvatarSlot({
    required this.profile,
    required this.sizeBucket,
    required this.size,
    required this.showStar,
    required this.isSelf,
  });

  final Profile profile;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final bool showStar;
  final bool isSelf;

  @override
  Widget build(BuildContext context) => TenturaAvatarStackRing(
    child: TenturaAvatar(
      profile: profile,
      sizeBucket: sizeBucket,
      size: size,
      showAuthorStar: showStar,
      isSelf: isSelf,
    ),
  );
}

class _PresenceDotSlot extends StatelessWidget {
  const _PresenceDotSlot({
    required this.userId,
    required this.size,
    required this.presence,
  });

  final String userId;
  final double size;
  final PresenceCubit presence;

  @override
  Widget build(BuildContext context) =>
      BlocSelector<PresenceCubit, Map<String, UserPresenceStatus>, bool>(
        bloc: presence,
        selector: (state) => state[userId] == UserPresenceStatus.online,
        builder: (_, isOnline) =>
            isOnline ? TenturaPresenceDot(size: size) : const SizedBox.shrink(),
      );
}
