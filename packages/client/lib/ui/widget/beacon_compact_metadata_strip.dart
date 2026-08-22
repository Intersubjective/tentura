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
import 'package:tentura/ui/widget/beacon_involved_people_face_pile.dart';

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
    if (!includeScheduleAndLocation) {
      return BeaconInvolvedPeopleFacePile.hasVisibleProfiles(
        beacon: beacon,
        involvedProfiles: involvedProfiles,
      );
    }
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
      includeScheduleAndLocation: includeScheduleAndLocation,
    )) {
      return const SizedBox.shrink();
    }

    final pile = BeaconInvolvedPeopleFacePile(
      beacon: beacon,
      involvedProfiles: involvedProfiles,
      currentUserId: currentUserId,
      onTap: onFacePileTap,
    );
    final hasPile = BeaconInvolvedPeopleFacePile.hasVisibleProfiles(
      beacon: beacon,
      involvedProfiles: involvedProfiles,
    );
    final hasSchedule =
        includeScheduleAndLocation && beacon.hasScheduleDates;
    final hasLocation = includeScheduleAndLocation &&
        (beacon.coordinates?.isNotEmpty ?? false);

    if (!hasPile && !hasSchedule && !hasLocation) {
      return const SizedBox.shrink();
    }

    // A freshly forwarded Request can briefly lay out its My Work card while
    // the surrounding route settles at compact width. In that state this row
    // may receive less than one metadata avatar's width. A bare face pile is a
    // non-flex Row child and would report its intrinsic width, overflowing the
    // row; Align instead accepts the available width and constrains the pile.
    if (hasPile && !hasSchedule && !hasLocation) {
      return ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          child: pile,
        ),
      );
    }

    return Row(
      children: [
        if (hasPile) pile,
        if (hasSchedule || hasLocation)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.maxWidth;
                final both = hasSchedule && hasLocation;
                final gap = both ? kSpacingSmall : 0.0;
                // Icon + gap inside [_ScheduleMeta] / [BeaconCardMetaItem].
                const scheduleChrome =
                    _LocationMeta.metaIconSize + _LocationMeta.metaIconGap;
                final locationReserve =
                    hasLocation ? _LocationMeta.layoutExtent : 0.0;
                final scheduleTextMax = hasSchedule
                    ? (both
                            ? available - gap - locationReserve - scheduleChrome
                            : _ScheduleMeta.textMaxWidth)
                        .clamp(0.0, _ScheduleMeta.textMaxWidth)
                    : 0.0;
                final locationMax = hasLocation
                    ? (both
                        ? available - gap - scheduleChrome - scheduleTextMax
                        : available)
                    : 0.0;

                return Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (hasSchedule)
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _ScheduleMeta(
                              beacon: beacon,
                              maxTextWidth: scheduleTextMax,
                            ),
                          ),
                        ),
                      if (both) SizedBox(width: gap),
                      if (hasLocation)
                        _LocationMeta(
                          beacon: beacon,
                          maxWidth: locationMax,
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

class _ScheduleMeta extends StatefulWidget {
  const _ScheduleMeta({
    required this.beacon,
    required this.maxTextWidth,
  });

  /// Cap for absolute date text (ellipsis beyond this).
  static const double textMaxWidth = 160;

  final Beacon beacon;
  final double maxTextWidth;

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
      child: ExcludeSemantics(
        child: BeaconCardMetaItem(
          icon: presentation.icon,
          child: presentation.visibleText.isEmpty
              ? const SizedBox.shrink()
              : ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widget.maxTextWidth),
                  child: Text(
                    presentation.visibleText,
                    style: textStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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

  static const double metaIconSize = 16;
  static const double metaIconGap = 4;
  /// Layout width for icon-only mode (tap target expands via [OverflowBox]).
  static const double layoutExtent = metaIconSize;
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
    return metaIconSize + metaIconGap + painter.width <= maxWidth;
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
      // Layout stays icon-sized so schedule+pin fit one row; hit target is 44×44
      // overflowing into adjacent whitespace (clipBehavior: Clip.none on parents).
      child = SizedBox(
        width: layoutExtent,
        height: layoutExtent,
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: _minTapExtent,
          maxWidth: _minTapExtent,
          minHeight: _minTapExtent,
          maxHeight: _minTapExtent,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => showBeaconLocationActions(context, beacon),
              borderRadius: tapRadius,
              child: Center(
                child: Icon(
                  TenturaIcons.location,
                  size: metaIconSize,
                  color: scheme.onSurfaceVariant,
                ),
              ),
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
      child: ExcludeSemantics(child: child),
    );
  }
}
