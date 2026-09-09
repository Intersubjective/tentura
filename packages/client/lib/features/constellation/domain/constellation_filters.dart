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

typedef ConstellationRequestRef = ({
  String id,
  Set<String> needs,
  String? primaryNeedSlug,
  DateTime? startAt,
  DateTime? endAt,
  String? addressLabel,
  bool hasCoordinates,
});

typedef ConstellationFilters = ({
  Set<String> capabilitySlugs,
  LocationFilter location,
  TimingFilter timing,
  bool includeUnspecified,
});

Set<String> filterRequestIds({
  required Iterable<ConstellationRequestRef> requests,
  required ConstellationFilters filters,
  required DateTime asOfUtc,
}) {
  final result = <String>{};
  for (final request in requests) {
    if (_matchesFilters(request, filters, asOfUtc)) {
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
  return _matchesCapability(request, filters) &&
      _matchesLocation(request, filters) &&
      _matchesTiming(request, filters, asOfUtc);
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
  return _capabilitySlugs(request).intersection(filters.capabilitySlugs).isNotEmpty;
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
    TimingFilterWithinDays(days: final days) =>
      _matchesWithinDays(request, filters, asOfUtc, days),
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
