import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_involved_profiles.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_location_actions.dart';
import 'package:tentura/ui/utils/beacon_schedule_presenter.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';

/// Compact people / schedule / location strip shared by My Work cards and beacon HUD.
class BeaconCompactMetadataStrip extends StatelessWidget {
  const BeaconCompactMetadataStrip({
    required this.beacon,
    required this.involvedProfiles,
    required this.currentUserId,
    this.onFacePileTap,
    this.includeScheduleAndLocation = true,
    super.key,
  });

  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;
  final VoidCallback? onFacePileTap;

  /// When false, only the face pile is shown (beacon HUD defers schedule/location
  /// to dedicated metadata table rows).
  final bool includeScheduleAndLocation;

  static const double _compactWrapWidth = 360;

  static bool hasVisibleContent({
    required Beacon beacon,
    required List<Profile> involvedProfiles,
    bool includeScheduleAndLocation = true,
  }) {
    final display = beaconInvolvedPeopleDisplay(
      author: beacon.author,
      helpOfferUsers: involvedProfiles,
      helpOfferCount: involvedProfiles.length,
    );
    final hasPile = display.visible.isNotEmpty;
    if (!includeScheduleAndLocation) {
      return hasPile;
    }
    final hasSchedule = beacon.hasScheduleDates;
    final hasLocation = beacon.coordinates?.isNotEmpty ?? false;
    return hasPile || hasSchedule || hasLocation;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasVisibleContent(
      beacon: beacon,
      involvedProfiles: involvedProfiles,
      includeScheduleAndLocation: includeScheduleAndLocation,
    )) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWrap =
            context.windowClass == WindowClass.compact &&
            constraints.maxWidth < _compactWrapWidth;
        return useWrap
            ? _MetadataWrapLayout(
                beacon: beacon,
                involvedProfiles: involvedProfiles,
                currentUserId: currentUserId,
                onFacePileTap: onFacePileTap,
                includeScheduleAndLocation: includeScheduleAndLocation,
              )
            : _MetadataRowLayout(
                beacon: beacon,
                involvedProfiles: involvedProfiles,
                currentUserId: currentUserId,
                onFacePileTap: onFacePileTap,
                includeScheduleAndLocation: includeScheduleAndLocation,
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
    this.includeScheduleAndLocation = true,
  });

  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;
  final VoidCallback? onFacePileTap;
  final bool includeScheduleAndLocation;

  @override
  Widget build(BuildContext context) {
    final pile = _FacePile(
      beacon: beacon,
      involvedProfiles: involvedProfiles,
      currentUserId: currentUserId,
      onTap: onFacePileTap,
    );
    final schedule = _ScheduleMeta(beacon: beacon);
    final hasPile = pile.hasProfiles;
    final hasSchedule =
        includeScheduleAndLocation && beacon.hasScheduleDates;
    final hasLocation = includeScheduleAndLocation &&
        (beacon.coordinates?.isNotEmpty ?? false);

    if (!hasPile && !hasSchedule && !hasLocation) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasPile) pile,
        if (hasSchedule || hasLocation)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.maxWidth;
                final locationMaxWidth = hasSchedule
                    ? available - kSpacingSmall - 160
                    : available;
                return Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasSchedule) schedule,
                      if (hasSchedule && hasLocation)
                        const SizedBox(width: kSpacingSmall),
                      if (hasLocation)
                        _LocationMeta(
                          beacon: beacon,
                          maxWidth: locationMaxWidth,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
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
    this.includeScheduleAndLocation = true,
  });

  final Beacon beacon;
  final List<Profile> involvedProfiles;
  final String currentUserId;
  final VoidCallback? onFacePileTap;
  final bool includeScheduleAndLocation;

  @override
  Widget build(BuildContext context) {
    final pile = _FacePile(
      beacon: beacon,
      involvedProfiles: involvedProfiles,
      currentUserId: currentUserId,
      onTap: onFacePileTap,
    );
    final schedule = _ScheduleMeta(beacon: beacon);
    final hasPile = pile.hasProfiles;
    final hasSchedule =
        includeScheduleAndLocation && beacon.hasScheduleDates;
    final hasLocation = includeScheduleAndLocation &&
        (beacon.coordinates?.isNotEmpty ?? false);

    if (!hasPile && !hasSchedule && !hasLocation) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasPile) pile,
        if (hasSchedule || hasLocation)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.maxWidth;
                final locationMaxWidth = hasSchedule
                    ? available - kSpacingSmall - 160
                    : available;
                return Wrap(
                  alignment: WrapAlignment.end,
                  spacing: kSpacingSmall,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasSchedule) schedule,
                    if (hasLocation)
                      _LocationMeta(
                        beacon: beacon,
                        maxWidth: locationMaxWidth,
                      ),
                  ],
                );
              },
            ),
          ),
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
    final radius = BorderRadius.circular(TenturaRadii.cardDense);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: child,
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
    if (beaconScheduleNeedsLiveTimer(widget.beacon)) {
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
            : ConstrainedBox(
                // Keep a long absolute date (e.g. a cross-year range) from
                // overflowing this compact strip — it ellipsizes instead.
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  presentation.visibleText,
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
      ),
    );
  }
}

class _LocationMeta extends StatelessWidget {
  const _LocationMeta({
    required this.beacon,
    this.maxWidth,
  });

  final Beacon beacon;
  final double? maxWidth;

  static const double _metaIconSize = 16;
  static const double _metaIconGap = 4;
  static const double _minTapExtent = 44;

  static bool _rowFitsWidth({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextDirection textDirection,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return false;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: textDirection,
    )..layout();
    return _metaIconSize + _metaIconGap + painter.width <= maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    final coords = beacon.coordinates;
    if (coords == null || coords.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final baseStyle = beaconCardUpdatedLineTextStyle(theme);
    final addressLabel = beacon.addressLabel?.trim();
    final displayLabel = addressLabel == null || addressLabel.isEmpty
        ? l10n.beaconCardLocationSet
        : addressLabel;
    final semanticsLabel = l10n.beaconCardLocationSemantics(displayLabel);

    final width = maxWidth;
    final textDirection = Directionality.of(context);
    final tapRadius = BorderRadius.circular(TenturaRadii.cardDense);
    final showIconOnly = width != null &&
        width.isFinite &&
        width > 0 &&
        !_rowFitsWidth(
          text: displayLabel,
          style: baseStyle,
          maxWidth: width,
          textDirection: textDirection,
        );

    Widget child;
    if (showIconOnly) {
      child = InkWell(
        onTap: () => showBeaconLocationActions(context, beacon),
        borderRadius: tapRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _minTapExtent,
            minHeight: _minTapExtent,
          ),
          child: Center(
            child: Icon(
              TenturaIcons.location,
              size: _metaIconSize,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      child = InkWell(
        onTap: () => showBeaconLocationActions(context, beacon),
        borderRadius: tapRadius,
        child: BeaconCardMetaItem(
          icon: TenturaIcons.location,
          child: Text(
            displayLabel,
            style: baseStyle,
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: child,
    );
  }
}
