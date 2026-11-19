import 'package:test/test.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';

NotificationIdentity _make({
  NotificationEntityKind entityKind = NotificationEntityKind.request,
  String? label = 'Fix the roof',
  bool tombstone = false,
  bool readable = true,
  String? actorName = 'Anna',
  bool actorHidden = false,
  String? relatedLabel = 'Other',
  bool expired = false,
  bool hasImage = false,
  bool isPostBud = false,
}) => NotificationIdentity(
  entityKind: entityKind,
  label: label,
  tombstone: tombstone,
  readable: readable,
  actorName: actorName,
  actorHidden: actorHidden,
  relatedLabel: relatedLabel,
  expired: expired,
  hasImage: hasImage,
  isPostBud: isPostBud,
);

void main() {
  group('NotificationIdentity.hidesNotification', () {
    test('hides an unreadable bud with no tombstone access', () {
      expect(_make(isPostBud: true, readable: false).hidesNotification, isTrue);
    });
    test('keeps the deleted-bud notice for a viewer who may see the tombstone',
        () {
      expect(
        _make(isPostBud: true, readable: false, tombstone: true)
            .hidesNotification,
        isFalse,
      );
    });
    test('never hides a non-bud or a readable bud', () {
      expect(_make(readable: false).hidesNotification, isFalse);
      expect(_make(isPostBud: true).hidesNotification, isFalse);
    });
  });

  group('NotificationIdentity value semantics', () {
    test('exposes the constructed fields', () {
      final id = _make(hasImage: true, expired: true);
      expect(id.entityKind, NotificationEntityKind.request);
      expect(id.label, 'Fix the roof');
      expect(id.tombstone, isFalse);
      expect(id.readable, isTrue);
      expect(id.actorName, 'Anna');
      expect(id.actorHidden, isFalse);
      expect(id.relatedLabel, 'Other');
      expect(id.expired, isTrue);
      expect(id.hasImage, isTrue);
    });

    test('equal fields give equal instances with equal hash codes', () {
      expect(_make(), _make());
      expect(_make().hashCode, _make().hashCode);
    });

    test('a difference in any single field makes instances unequal', () {
      final base = _make();
      final variants = <String, NotificationIdentity>{
        'entityKind': _make(entityKind: NotificationEntityKind.post),
        'label': _make(label: 'Other title'),
        'tombstone': _make(tombstone: true),
        'readable': _make(readable: false),
        'actorName': _make(actorName: 'Bob'),
        'actorHidden': _make(actorHidden: true),
        'relatedLabel': _make(relatedLabel: null),
        'expired': _make(expired: true),
        'hasImage': _make(hasImage: true),
      };
      for (final MapEntry(key: field, value: other) in variants.entries) {
        expect(base == other, isFalse, reason: '$field must affect ==');
      }
    });
  });
}
