enum LocationFilter {
  any,
  hasLocation,
  unspecified,
}

sealed class TimingFilter {
  const TimingFilter();
}

final class TimingFilterAny extends TimingFilter {
  const TimingFilterAny();
}

final class TimingFilterUndated extends TimingFilter {
  const TimingFilterUndated();
}

final class TimingFilterWithinDays extends TimingFilter {
  const TimingFilterWithinDays(this.days);

  final int days;
}

const timingFilterAny = TimingFilterAny();
const timingFilterUndated = TimingFilterUndated();

TimingFilterWithinDays timingFilterWithinDays(int days) =>
    TimingFilterWithinDays(days);

sealed class ActivityRecencyFilter {
  const ActivityRecencyFilter();
}

final class ActivityRecencyFilterAny extends ActivityRecencyFilter {
  const ActivityRecencyFilterAny();
}

final class ActivityRecencyFilterWithinDays extends ActivityRecencyFilter {
  const ActivityRecencyFilterWithinDays(this.days);

  final int days;
}

const activityRecencyFilterAny = ActivityRecencyFilterAny();

ActivityRecencyFilterWithinDays activityRecencyFilterWithinDays(int days) =>
    ActivityRecencyFilterWithinDays(days);

typedef ConstellationRequestRef = ({
  String id,
  Set<String> needs,
  String? primaryNeedSlug,
  DateTime? startAt,
  DateTime? endAt,
  DateTime? lastActivityAt,
  String? addressLabel,
  bool hasCoordinates,
});

typedef ConstellationFilters = ({
  Set<String> capabilitySlugs,
  LocationFilter location,
  TimingFilter timing,
  ActivityRecencyFilter activityRecency,
  bool includeUnspecified,
});

Set<String> filterRequestIds({
  required Iterable<ConstellationRequestRef> requests,
  required ConstellationFilters filters,
  required DateTime asOfUtc,
  Set<String> activityRecencyExemptIds = const {},
}) {
  final result = <String>{};
  for (final request in requests) {
    if (activityRecencyExemptIds.contains(request.id)) {
      if (_matchesFiltersExceptActivityRecency(request, filters, asOfUtc)) {
        result.add(request.id);
      }
    } else if (_matchesFilters(request, filters, asOfUtc)) {
      result.add(request.id);
    }
  }
  return result;
}

bool _matchesFilters(
  ConstellationRequestRef request,
  ConstellationFilters filters,
  DateTime asOfUtc,
) {
  return _matchesFiltersExceptActivityRecency(request, filters, asOfUtc) &&
      _matchesActivityRecency(request, filters, asOfUtc);
}

bool _matchesFiltersExceptActivityRecency(
  ConstellationRequestRef request,
  ConstellationFilters filters,
  DateTime asOfUtc,
) {
  return _matchesCapability(request, filters) &&
      _matchesLocation(request, filters) &&
      _matchesTiming(request, filters, asOfUtc);
}

bool _matchesActivityRecency(
  ConstellationRequestRef request,
  ConstellationFilters filters,
  DateTime asOfUtc,
) {
  return switch (filters.activityRecency) {
    ActivityRecencyFilterAny() => true,
    ActivityRecencyFilterWithinDays(:final days) =>
      _activityWithinDays(request.lastActivityAt, asOfUtc, days),
  };
}

bool _activityWithinDays(
  DateTime? lastActivityAt,
  DateTime asOfUtc,
  int days,
) {
  if (lastActivityAt == null) {
    return false;
  }
  final cutoff = asOfUtc.subtract(Duration(days: days));
  return !lastActivityAt.isBefore(cutoff);
}

int compareConstellationBeaconRecency({
  required String aId,
  required String bId,
  required Map<String, DateTime?> lastActivityAtById,
}) {
  final bActivity = lastActivityAtById[bId];
  final aActivity = lastActivityAtById[aId];
  if (bActivity != null && aActivity != null) {
    final byActivity = bActivity.compareTo(aActivity);
    if (byActivity != 0) {
      return byActivity;
    }
  } else if (bActivity != null) {
    return -1;
  } else if (aActivity != null) {
    return 1;
  }
  return aId.compareTo(bId);
}

void sortConstellationBeaconIdsByRecency(
  List<String> ids,
  Map<String, DateTime?> lastActivityAtById,
) {
  ids.sort(
    (a, b) => compareConstellationBeaconRecency(
      aId: a,
      bId: b,
      lastActivityAtById: lastActivityAtById,
    ),
  );
}

Set<String> _capabilitySlugs(ConstellationRequestRef request) {
  final slugs = <String>{...request.needs};
  final primary = request.primaryNeedSlug?.trim();
  if (primary != null && primary.isNotEmpty) {
    slugs.add(primary);
  }
  return slugs;
}

bool _capabilityUnspecified(ConstellationRequestRef request) =>
    _capabilitySlugs(request).isEmpty;

bool _matchesCapability(
  ConstellationRequestRef request,
  ConstellationFilters filters,
) {
  if (filters.capabilitySlugs.isEmpty) {
    return true;
  }
  if (_capabilityUnspecified(request)) {
    return filters.includeUnspecified;
  }
  return _capabilitySlugs(
    request,
  ).intersection(filters.capabilitySlugs).isNotEmpty;
}

bool _hasLocation(ConstellationRequestRef request) {
  return request.hasCoordinates ||
      (request.addressLabel?.trim().isNotEmpty ?? false);
}

bool _matchesLocation(
  ConstellationRequestRef request,
  ConstellationFilters filters,
) {
  return switch (filters.location) {
    LocationFilter.any => true,
    LocationFilter.hasLocation => _hasLocation(request),
    LocationFilter.unspecified => !_hasLocation(request),
  };
}

bool _timingUnspecified(ConstellationRequestRef request) =>
    request.startAt == null && request.endAt == null;

bool _matchesTiming(
  ConstellationRequestRef request,
  ConstellationFilters filters,
  DateTime asOfUtc,
) {
  return switch (filters.timing) {
    TimingFilterAny() => true,
    TimingFilterUndated() => _timingUnspecified(request),
    TimingFilterWithinDays(:final days) => _matchesWithinDays(
      request,
      filters,
      asOfUtc,
      days,
    ),
  };
}

bool _matchesWithinDays(
  ConstellationRequestRef request,
  ConstellationFilters filters,
  DateTime asOfUtc,
  int days,
) {
  if (_timingUnspecified(request)) {
    return filters.includeUnspecified;
  }

  final intervalStart = asOfUtc;
  final intervalEnd = asOfUtc.add(Duration(days: days));

  final startAt = request.startAt;
  final endAt = request.endAt;

  if (startAt == null && endAt != null) {
    return !_isBefore(endAt, intervalStart) && !_isAfter(endAt, intervalEnd);
  }

  if (startAt != null) {
    final eventStart = startAt;
    final eventEnd = endAt ?? startAt;
    return _closedIntervalsOverlap(
      eventStart,
      eventEnd,
      intervalStart,
      intervalEnd,
    );
  }

  return false;
}

bool _closedIntervalsOverlap(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) {
  return !_isAfter(aStart, bEnd) && !_isAfter(bStart, aEnd);
}

bool _isBefore(DateTime a, DateTime b) => a.compareTo(b) < 0;

bool _isAfter(DateTime a, DateTime b) => a.compareTo(b) > 0;
