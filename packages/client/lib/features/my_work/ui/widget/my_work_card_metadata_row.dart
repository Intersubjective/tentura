import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/app/platform/platform_info.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_involved_profiles.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/features/geo/ui/widget/place_name_text.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_highlight.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_schedule_presenter.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/overlapping_people_avatars.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

/// My Work list card metadata: face pile + schedule countdown + location.
class MyWorkCardMetadataRow extends StatelessWidget {
  const MyWorkCardMetadataRow({
    required this.beacon,
    required this.viewModel,
    required this.currentUserId,
    required this.highlight,
    super.key,
  });

  final Beacon beacon;
  final MyWorkCardViewModel viewModel;
  final String currentUserId;
  final MyWorkCardHighlightKind highlight;

  static const double _compactWrapWidth = 320;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final useWrap =
                context.windowClass == WindowClass.compact &&
                constraints.maxWidth < _compactWrapWidth;
            return useWrap
                ? _MetadataWrapLayout(beacon: beacon)
                : _MetadataRowLayout(beacon: beacon);
          },
        ),
        MyWorkLastEventRow(
          beacon: beacon,
          viewModel: viewModel,
          currentUserId: currentUserId,
          highlight: highlight,
        ),
      ],
    );
  }
}

class _MetadataRowLayout extends StatelessWidget {
  const _MetadataRowLayout({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final pile = _FacePile(beacon: beacon);
    final schedule = _MyWorkScheduleMeta(beacon: beacon);
    final location = _MyWorkLocationMeta(beacon: beacon);
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
  const _MetadataWrapLayout({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final pile = _FacePile(beacon: beacon);
    final schedule = _MyWorkScheduleMeta(beacon: beacon);
    final location = _MyWorkLocationMeta(beacon: beacon);
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
  const _FacePile({required this.beacon});

  final Beacon beacon;

  bool get hasProfiles {
    final display = beaconInvolvedPeopleDisplay(
      author: beacon.author,
      helpOfferUsers: beacon.helpOfferUsers,
      helpOfferCount: beacon.helpOfferCount,
    );
    return display.visible.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final metaAvatar = context.tt.metadataAvatarSize;
    final display = beaconInvolvedPeopleDisplay(
      author: beacon.author,
      helpOfferUsers: beacon.helpOfferUsers,
      helpOfferCount: beacon.helpOfferCount,
    );
    if (display.visible.isEmpty) {
      return const SizedBox.shrink();
    }
    return OverlappingPeopleAvatars(
      profiles: display.visible,
      overflowCount: display.overflow,
      size: metaAvatar,
      starredProfileId: beacon.author.id,
      semanticsLabel: l10n.facepileSemantics(
        display.visible.length,
        display.overflow,
      ),
    );
  }
}

class _MyWorkScheduleMeta extends StatefulWidget {
  const _MyWorkScheduleMeta({required this.beacon});

  final Beacon beacon;

  @override
  State<_MyWorkScheduleMeta> createState() => _MyWorkScheduleMetaState();
}

class _MyWorkScheduleMetaState extends State<_MyWorkScheduleMeta> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(covariant _MyWorkScheduleMeta oldWidget) {
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

class _MyWorkLocationMeta extends StatelessWidget {
  const _MyWorkLocationMeta({required this.beacon});

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

/// Place name for card metadata — prefers city/locality when available.
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
