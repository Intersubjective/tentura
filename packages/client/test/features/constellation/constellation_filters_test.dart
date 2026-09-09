import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_filters.dart';

ConstellationRequestRef _request({
  required String id,
  Set<String> needs = const {},
  String? primaryNeedSlug,
  DateTime? startAt,
  DateTime? endAt,
  String? addressLabel,
  bool hasCoordinates = false,
}) {
  return (
    id: id,
    needs: needs,
    primaryNeedSlug: primaryNeedSlug,
    startAt: startAt,
    endAt: endAt,
    addressLabel: addressLabel,
    hasCoordinates: hasCoordinates,
  );
}

ConstellationFilters _filters({
  Set<String> capabilitySlugs = const {},
  LocationFilter location = LocationFilter.any,
  TimingFilter timing = timingFilterAny,
  bool includeUnspecified = true,
}) {
  return (
    capabilitySlugs: capabilitySlugs,
    location: location,
    timing: timing,
    includeUnspecified: includeUnspecified,
  );
}

void main() {
  group('filterRequestIds', () {
    test('clearing filters returns the original id set exactly', () {
      final requests = [
        _request(id: 'a'),
        _request(id: 'b', needs: {'drill'}),
        _request(id: 'c', endAt: DateTime.utc(2026, 1, 1)),
      ];
      final originalIds = requests.map((r) => r.id).toSet();

      final filtered = filterRequestIds(
        requests: requests,
        filters: _filters(),
        asOfUtc: DateTime.utc(2026, 6, 1),
      );

      expect(filtered, originalIds);
    });

    group('capability', () {
      test('unspecified capability follows includeUnspecified in identified group', () {
        final unspecified = _request(id: 'unspecified');
        final requests = [unspecified];

        final retained = filterRequestIds(
          requests: requests,
          filters: _filters(capabilitySlugs: {'drill'}),
          asOfUtc: DateTime.utc(2026, 6, 1),
        );
        expect(retained, {'unspecified'});

        final excluded = filterRequestIds(
          requests: requests,
          filters: _filters(
            capabilitySlugs: {'drill'},
            includeUnspecified: false,
          ),
          asOfUtc: DateTime.utc(2026, 6, 1),
        );
        expect(excluded, isEmpty);
      });

      test('needs match without primaryNeedSlug', () {
        final request = _request(id: 'r1', needs: {'drill'});
        final filtered = filterRequestIds(
          requests: [request],
          filters: _filters(capabilitySlugs: {'drill'}),
          asOfUtc: DateTime.utc(2026, 6, 1),
        );
        expect(filtered, {'r1'});
      });

      test('primaryNeedSlug contributes to capability union', () {
        final request = _request(id: 'r1', primaryNeedSlug: 'drill');
        final filtered = filterRequestIds(
          requests: [request],
          filters: _filters(capabilitySlugs: {'drill'}),
          asOfUtc: DateTime.utc(2026, 6, 1),
        );
        expect(filtered, {'r1'});
      });
    });

    group('location', () {
      test('unspecified selects requests with neither address nor coordinates', () {
        final noLocation = _request(id: 'none');
        final withLabel = _request(id: 'label', addressLabel: 'Main St');
        final withCoords = _request(id: 'coords', hasCoordinates: true);
        final blankLabel = _request(id: 'blank', addressLabel: '   ');

        final filtered = filterRequestIds(
          requests: [noLocation, withLabel, withCoords, blankLabel],
          filters: _filters(location: LocationFilter.unspecified),
          asOfUtc: DateTime.utc(2026, 6, 1),
        );

        expect(filtered, {'none', 'blank'});
      });

      test('no request is classified remote', () {
        final remoteLike = _request(id: 'remote', addressLabel: 'Remote');
        final filtered = filterRequestIds(
          requests: [remoteLike],
          filters: _filters(location: LocationFilter.unspecified),
          asOfUtc: DateTime.utc(2026, 6, 1),
        );
        expect(filtered, isEmpty);
      });

      test('hasLocation matches address or coordinates', () {
        final withLabel = _request(id: 'label', addressLabel: 'Park');
        final withCoords = _request(id: 'coords', hasCoordinates: true);
        final neither = _request(id: 'neither');

        final filtered = filterRequestIds(
          requests: [withLabel, withCoords, neither],
          filters: _filters(location: LocationFilter.hasLocation),
          asOfUtc: DateTime.utc(2026, 6, 1),
        );

        expect(filtered, {'label', 'coords'});
      });
    });

    group('timing withinDays', () {
      final asOfUtc = DateTime.utc(2026, 6, 1, 12);
      const days = 7;
      final intervalEnd = asOfUtc.add(const Duration(days: days));
      final timing = timingFilterWithinDays(days);

      test('deadline exactly at asOfUtc is included', () {
        final request = _request(id: 'd', endAt: asOfUtc);
        final filtered = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing),
          asOfUtc: asOfUtc,
        );
        expect(filtered, {'d'});
      });

      test('deadline exactly at asOfUtc + n days is included', () {
        final request = _request(id: 'd', endAt: intervalEnd);
        final filtered = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing),
          asOfUtc: asOfUtc,
        );
        expect(filtered, {'d'});
      });

      test('deadline one second past asOfUtc + n days is excluded', () {
        final request = _request(
          id: 'd',
          endAt: intervalEnd.add(const Duration(seconds: 1)),
        );
        final filtered = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing),
          asOfUtc: asOfUtc,
        );
        expect(filtered, isEmpty);
      });

      test('deadline one second before asOfUtc is excluded', () {
        final request = _request(
          id: 'd',
          endAt: asOfUtc.subtract(const Duration(seconds: 1)),
        );
        final filtered = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing),
          asOfUtc: asOfUtc,
        );
        expect(filtered, isEmpty);
      });

      test('event overlapping the interval is included', () {
        final request = _request(
          id: 'e',
          startAt: asOfUtc.subtract(const Duration(days: 2)),
          endAt: asOfUtc.add(const Duration(days: 1)),
        );
        final filtered = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing),
          asOfUtc: asOfUtc,
        );
        expect(filtered, {'e'});
      });

      test('undated request follows includeUnspecified', () {
        final request = _request(id: 'u');

        final included = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing),
          asOfUtc: asOfUtc,
        );
        expect(included, {'u'});

        final excluded = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing, includeUnspecified: false),
          asOfUtc: asOfUtc,
        );
        expect(excluded, isEmpty);
      });

      test('different asOfUtc changes the result', () {
        final deadline = asOfUtc.add(const Duration(days: 3));
        final request = _request(id: 'd', endAt: deadline);

        final included = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing),
          asOfUtc: asOfUtc,
        );
        expect(included, {'d'});

        final excluded = filterRequestIds(
          requests: [request],
          filters: _filters(timing: timing),
          asOfUtc: deadline.add(const Duration(days: 1)),
        );
        expect(excluded, isEmpty);
      });
    });

    group('timing undated', () {
      test('selects only undated requests', () {
        final undated = _request(id: 'u');
        final deadline = _request(id: 'd', endAt: DateTime.utc(2026, 6, 2));
        final event = _request(
          id: 'e',
          startAt: DateTime.utc(2026, 6, 2),
        );

        final filtered = filterRequestIds(
          requests: [undated, deadline, event],
          filters: _filters(timing: timingFilterUndated),
          asOfUtc: DateTime.utc(2026, 6, 1),
        );

        expect(filtered, {'u'});
      });
    });

    test('returns request ids only and takes no person input', () {
      final requests = [_request(id: 'only-id')];
      final filtered = filterRequestIds(
        requests: requests,
        filters: _filters(),
        asOfUtc: DateTime.utc(2026, 6, 1),
      );
      expect(filtered, isA<Set<String>>());
      expect(filtered, {'only-id'});
    });
  });
}
