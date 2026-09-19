import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/for_you_stream_entries.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card_mapper.dart';

const _provenance = '''
{"senders":[{"id":"s1","displayName":"Bai Yue","notePreview":"look at this",
"reasonSlugs":["repair"],"mr":0.4}],"totalDistinctSenders":2,
"strongestNotePreview":"look at this",
"latestNoteForward":{"forwardId":"fw1","senderId":"s1","displayName":"Bai Yue",
"notePreview":"look at this","forwardedAt":"2026-09-10T09:00:00Z",
"reasonSlugs":["repair"]}}''';

AttentionReceipt _grouped({
  String? provenanceJson = _provenance,
  int eventUnseenCount = 2,
  List<AttentionReceipt> eventsPreview = const [],
}) => AttentionReceipt(
  id: 'activity-beacon:b1',
  category: 'coordination',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: 'Our requirements',
  body: '',
  actionUrl: '/#/view?id=b1',
  createdAt: DateTime.utc(2026, 9, 10, 12),
  collapsedCount: 0,
  presentationKey: 'request_status_changed',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  itemKind: AttentionItemKind.requestActivity,
  beaconId: 'b1',
  eventTotal: 5,
  eventUnseenCount: eventUnseenCount,
  eventsPreview: eventsPreview,
  provenanceJson: provenanceJson,
  beaconAuthorId: 'author-1',
  beaconAuthorName: 'Anna',
  beaconAuthorImageId: 'img-a',
  beaconImageId: 'cover-1',
  beaconEndAt: DateTime.utc(2026, 9, 20),
  allowsForward: true,
);

void main() {
  group('grouped receipt → card', () {
    test('rebuilds the Request the header needs', () {
      final model = requestCardFromReceipt(
        _grouped(),
        relation: ForYouStreamRelation.following,
      )!;

      expect(model.beacon.id, 'b1');
      expect(model.beacon.title, 'Our requirements');
      expect(model.beacon.author.id, 'author-1');
      expect(model.beacon.author.displayName, 'Anna');
      expect(model.beacon.author.image?.id, 'img-a');
      expect(model.beacon.coverImageId, 'cover-1');
      expect(model.beacon.endAt, DateTime.utc(2026, 9, 20));
      expect(model.allowsForward, isTrue);
      expect(model.variant, RequestAttentionCardVariant.grouped);
      expect(model.relation, RequestAttentionRelation.following);
    });

    test('carries the note the card is the only home for (§12.1, A7)', () {
      final model = requestCardFromReceipt(_grouped())!;

      expect(model.provenance.latestNoteForward?.notePreview, 'look at this');
      expect(model.provenance.latestNoteForward?.senderId, 's1');
      expect(model.provenance.senders.single.reasonSlugs, ['repair']);
      expect(model.provenance.totalDistinctSenders, 2);
    });

    test('an absent or unreadable provenance is empty, never a throw', () {
      expect(
        requestCardFromReceipt(_grouped(provenanceJson: null))!.provenance,
        same(InboxProvenance.empty),
      );
      expect(
        requestCardFromReceipt(_grouped(provenanceJson: 'not json'))!.provenance,
        same(InboxProvenance.empty),
      );
    });

    test('the dot comes from the server\'s uncleared count (§6 M1)', () {
      expect(
        requestCardFromReceipt(_grouped(eventUnseenCount: 2))!
            .facts
            .unclearedOptionalEvents,
        2,
      );
      expect(
        requestCardFromReceipt(_grouped(eventUnseenCount: 0))!
            .facts
            .unclearedOptionalEvents,
        0,
      );
    });

    test('a beacon-less receipt is not a Request card', () {
      expect(
        requestCardFromReceipt(
          _grouped().copyWith(beaconId: null),
        ),
        isNull,
      );
    });
  });

  group('pinned inbox item → card', () {
    InboxItem item({InboxProvenance? provenance}) => InboxItem(
      beaconId: 'b2',
      latestForwardAt: DateTime.utc(2026, 9, 11),
      status: InboxItemStatus.needsMe,
      provenance: provenance ?? InboxProvenance.parse(_provenance),
      beacon: Beacon(
        id: 'b2',
        title: 'Need a trailer',
        author: const Profile(id: 'author-2', displayName: 'Gleb'),
        createdAt: DateTime.utc(2026, 9),
        updatedAt: DateTime.utc(2026, 9),
      ),
    );

    test('is pinned, with no relation yet (§6.1)', () {
      final model = requestCardFromInboxItem(item())!;

      expect(model.variant, RequestAttentionCardVariant.pinned);
      expect(model.relation, RequestAttentionRelation.none);
      expect(model.beacon.title, 'Need a trailer');
    });

    test('an unanswered forward is pending, which lights For You (§6)', () {
      expect(requestCardFromInboxItem(item())!.facts.pendingForward, isTrue);
    });

    test('carries the item\'s own provenance, not a re-parse', () {
      final model = requestCardFromInboxItem(item())!;

      expect(model.provenance.latestNoteForward?.notePreview, 'look at this');
    });

    test('an item with no beacon cannot be drawn', () {
      expect(
        requestCardFromInboxItem(
          item().copyWith(beacon: null),
        ),
        isNull,
      );
    });
  });
}
