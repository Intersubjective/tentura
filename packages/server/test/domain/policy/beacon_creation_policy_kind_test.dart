import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/beacon_creation_policy.dart';

Matcher _createError(Pattern pattern) => throwsA(
  isA<BeaconCreateException>().having(
    (e) => e.description,
    'description',
    matches(pattern),
  ),
);

void main() {
  group('BeaconCreationPolicy kind-aware validation', () {
    group('Post', () {
      test('accepts a Post with every content field empty', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: '',
            isDiscoverable: false,
          ),
          returnsNormally,
        );
      });

      test('accepts an empty description when normalizing a Post', () {
        expect(
          BeaconCreationPolicy.normalizeStandaloneDescription(
            '',
            kind: BeaconKind.post,
          ),
          '',
        );
      });

      test('rejects a Post with a title', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: 'x',
            description: '',
            isDiscoverable: false,
          ),
          _createError(RegExp('title', caseSensitive: false)),
        );
      });

      test('rejects a Post with a description', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: 'text',
            isDiscoverable: false,
          ),
          _createError(RegExp('description', caseSensitive: false)),
        );
      });

      test('rejects a Post with needs', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: '',
            needs: const {'transport'},
            isDiscoverable: false,
          ),
          throwsA(isA<BeaconCreateException>()),
        );
      });

      test('rejects a Post with a schedule', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: '',
            startAt: DateTime.utc(2026, 10, 3),
            isDiscoverable: false,
          ),
          throwsA(isA<BeaconCreateException>()),
        );
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: '',
            endAt: DateTime.utc(2026, 10, 3),
            isDiscoverable: false,
          ),
          throwsA(isA<BeaconCreateException>()),
        );
      });

      test('rejects a discoverable Post', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: '',
            isDiscoverable: true,
          ),
          throwsA(isA<BeaconCreateException>()),
        );
      });

      test('rejects a Post with a parent', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: '',
            isDiscoverable: false,
            parentBeaconId: 'Bparent000001',
          ),
          _createError(RegExp('parent', caseSensitive: false)),
        );
      });

      test('rejects a Post with a primary need slug', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: '',
            primaryNeedSlug: 'transport',
            isDiscoverable: false,
          ),
          throwsA(isA<BeaconCreateException>()),
        );
      });

      test('rejects a Post with a cover image', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.post,
            title: '',
            description: '',
            hasCover: true,
            isDiscoverable: false,
          ),
          throwsA(isA<BeaconCreateException>()),
        );
      });
    });

    group('publish title entry point', () {
      test('allows an empty title for a Post', () {
        expect(
          () => BeaconCreationPolicy.assertPublishTitle(
            '',
            kind: BeaconKind.post,
          ),
          returnsNormally,
        );
      });

      test('requires a title for a Request', () {
        expect(
          () => BeaconCreationPolicy.assertPublishTitle(
            '  ',
            kind: BeaconKind.request,
          ),
          _createError('Title is required'),
        );
      });
    });

    group('Request', () {
      test('rejects an empty title', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.request,
            title: '',
            description: 'Needs help',
            isDiscoverable: true,
          ),
          _createError('Title is required'),
        );
      });

      test('rejects a whitespace-only title', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.request,
            title: '   ',
            description: 'Needs help',
            isDiscoverable: true,
          ),
          _createError('Title is required'),
        );
      });

      test('accepts a titled Request', () {
        expect(
          () => BeaconCreationPolicy.assertKindFields(
            kind: BeaconKind.request,
            title: 'Need a ride',
            description: 'Needs help',
            isDiscoverable: true,
          ),
          returnsNormally,
        );
      });

      test('still requires a description', () {
        expect(
          () => BeaconCreationPolicy.normalizeStandaloneDescription(
            '',
            kind: BeaconKind.request,
          ),
          _createError('Description is required'),
        );
      });
    });
  });
}
