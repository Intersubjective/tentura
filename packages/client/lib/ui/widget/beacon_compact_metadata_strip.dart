import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/app/platform/platform_info.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_involved_profiles.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/geo/ui/widget/place_name_text.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_schedule_presenter.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

/// Compact people / schedule / location strip shared by My Work cards and beacon HUD.
class BeaconCompactMetadataStrip extends StatelessWidget {
  const BeaconCompactMetadataStrip({
    required this.beacon,
    required this.involvedProfiles,
    required this.currentUserId,
    this.onFacePileTap,
    super.key,
  });

  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;
  final VoidCallback? onFacePileTap;

  static const double _compactWrapWidth = 360;

  static bool hasVisibleContent({
    required Beacon beacon,
    required List<Profile> involvedProfiles,
  }) {
    final display = beaconInvolvedPeopleDisplay(
      author: beacon.author,
      helpOfferUsers: involvedProfiles,
      helpOfferCount: involvedProfiles.length,
    );
    final hasPile = display.visible.isNotEmpty;
    final hasSchedule = beacon.hasScheduleDates;
    final hasLocation = beacon.coordinates?.isNotEmpty ?? false;
    return hasPile || hasSchedule || hasLocation;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasVisibleContent(
      beacon: beacon,
      involvedProfiles: involvedProfiles,
    )) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyWidth = constraints.maxWidth - kBeaconHudRowLeadWidth;
        final useWrap =
            context.windowClass == WindowClass.compact &&
            bodyWidth < _compactWrapWidth;
        final strip = useWrap
            ? _MetadataWrapLayout(
                beacon: beacon,
                involvedProfiles: involvedProfiles,
                currentUserId: currentUserId,
                onFacePileTap: onFacePileTap,
              )
            : _MetadataRowLayout(
                beacon: beacon,
                involvedProfiles: involvedProfiles,
                currentUserId: currentUserId,
                onFacePileTap: onFacePileTap,
              );

        return BeaconHudIconRow(
          leadIcon: BeaconHudRowIcons.people,
          semanticsLabel: l10n.beaconHudPeopleRowSemantics,
          leadAlign: BeaconHudRowLeadAlign.center,
          body: strip,
        );
      },
    );
  }
}

class _MetadataRowLayout extends StatelessWidget {
  const _MetadataRowLayout({
    required this.beacon,
    required this.involvedProfiles,
    required this.currentUserId,
    this.onFacePileTap,
  });

  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;
  final VoidCallback? onFacePileTap;

  @override
  Widget build(BuildContext context) {
    final pile = _FacePile(
      beacon: beacon,
      involvedProfiles: involvedProfiles,
      currentUserId: currentUserId,
      onTap: onFacePileTap,
    );
    final schedule = _ScheduleMeta(beacon: beacon);
    final location = _LocationMeta(beacon: beacon);
    final hasPile = pile.hasProfiles;
    final hasSchedule = beacon.hasScheduleDates;
    final hasLocation = beacon.coordinates?.isNotEmpty ?? false;

    if (!hasPile && !hasSchedule && !hasLocation) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasPile) pile,
        if (hasPile && (hasSchedule || hasLocation))
          const SizedBox(width: kSpacingSmall),
        if (hasSchedule) Flexible(child: schedule),
        if (hasSchedule && hasLocation) const SizedBox(width: kSpacingSmall),
        if (hasLocation) Expanded(child: location),
      ],
    );
  }
}

class _MetadataWrapLayout extends StatelessWidget {
  const _MetadataWrapLayout({
    required this.beacon,
    required this.involvedProfiles,
    required this.currentUserId,
    this.onFacePileTap,
  });

  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;
  final VoidCallback? onFacePileTap;

  @override
  Widget build(BuildContext context) {
    final pile = _FacePile(
      beacon: beacon,
      involvedProfiles: involvedProfiles,
      currentUserId: currentUserId,
      onTap: onFacePileTap,
    );
    final schedule = _ScheduleMeta(beacon: beacon);
    final location = _LocationMeta(beacon: beacon);
    final hasPile = pile.hasProfiles;
    final hasSchedule = beacon.hasScheduleDates;
    final hasLocation = beacon.coordinates?.isNotEmpty ?? false;

    if (!hasPile && !hasSchedule && !hasLocation) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: kSpacingSmall,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasPile) pile,
        if (hasSchedule) schedule,
        if (hasLocation) location,
      ],
    );
  }
}

class _FacePile extends StatelessWidget {
  const _FacePile({
    required this.beacon,
    required this.involvedProfiles,
    required this.currentUserId,
    this.onTap,
  });

  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;
  final VoidCallback? onTap;

  bool get hasProfiles {
    final display = beaconInvolvedPeopleDisplay(
      author: beacon.author,
      helpOfferUsers: involvedProfiles,
      helpOfferCount: involvedProfiles.length,
    );
    return display.visible.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final metaAvatar = context.tt.metadataAvatarSize;
    final display = beaconInvolvedPeopleDisplay(
      author: beacon.author,
      helpOfferUsers: involvedProfiles,
      helpOfferCount: involvedProfiles.length,
    );
    if (display.visible.isEmpty) {
      return const SizedBox.shrink();
    }
    final child = OverlappingPeopleAvatars(
      profiles: display.visible,
      overflowCount: display.overflow,
      size: metaAvatar,
      starredProfileId: beacon.author.id,
      selfUserId: currentUserId,
      semanticsLabel: l10n.facepileSemantics(
        display.visible.length,
        display.overflow,
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    );
  }
}

class _ScheduleMeta extends StatefulWidget {
  const _ScheduleMeta({required this.beacon});

  final Beacon beacon;

  @override
  State<_ScheduleMeta> createState() => _ScheduleMetaState();
}

class _ScheduleMetaState extends State<_ScheduleMeta> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(covariant _ScheduleMeta oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beacon.id != widget.beacon.id ||
        oldWidget.beacon.startAt != widget.beacon.startAt ||
        oldWidget.beacon.endAt != widget.beacon.endAt) {
      _timer?.cancel();
      _timer = null;
      _maybeStartTimer();
    }
  }

  void _maybeStartTimer() {
    final phase = widget.beacon.schedulePhase();
    if (beaconScheduleNeedsLiveTimer(phase)) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
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
    final presentation = beaconSchedulePresentation(
      beacon: widget.beacon,
      l10n: l10n,
    );
    if (presentation == null) {
      return const SizedBox.shrink();
    }

    final baseStyle = beaconCardUpdatedLineTextStyle(theme);
    final textStyle = TenturaText.withTabular(
      baseStyle.copyWith(
        color: presentation.urgent ? scheme.error : baseStyle.color,
      ),
    );

    return Semantics(
      label: presentation.semanticsLabel,
      child: BeaconCardMetaItem(
        icon: presentation.icon,
        child: presentation.visibleText.isEmpty
            ? const SizedBox.shrink()
            : Text(
                presentation.visibleText,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }
}

class _LocationMeta extends StatelessWidget {
  const _LocationMeta({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final coords = beacon.coordinates;
    if (coords == null || coords.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final baseStyle = beaconCardUpdatedLineTextStyle(theme);
    final useStaticLabel = kIsWeb || isDesktopPlatform;

    final label = useStaticLabel
        ? Text(
            l10n.beaconCardLocationSet,
            style: baseStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : _CompactPlaceNameText(
            coords: coords,
            style: baseStyle,
          );

    return Semantics(
      label: l10n.beaconCardLocationSemantics(
        useStaticLabel ? l10n.beaconCardLocationSet : coords.toString(),
      ),
      child: BeaconCardMetaItem(
        icon: TenturaIcons.location,
        mainAxisSize: MainAxisSize.max,
        child: Expanded(child: label),
      ),
    );
  }
}

class _CompactPlaceNameText extends StatelessWidget {
  const _CompactPlaceNameText({
    required this.coords,
    this.style,
  });

  final Coordinates coords;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return PlaceNameText(
      coords: coords,
      style: style,
      labelForPlace: (place, coords) =>
          place?.displayLocality ?? coords.toString(),
    );
  }
}
