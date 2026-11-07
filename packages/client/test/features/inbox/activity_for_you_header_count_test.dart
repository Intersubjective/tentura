import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_state.dart';
import 'package:tentura/features/inbox/ui/widget/activity_for_you_header_count.dart';

void main() {
  const base = ActivityOffersState();

  test('no aggregate when pinned list is empty and fully loaded', () {
    expect(
      activityForYouHeaderCount(
        offersState: base.copyWith(totalCount: 1, hasMore: false),
        visiblePinnedCount: 0,
      ),
      isNull,
    );
  });

  test('matches visible cards when fully loaded', () {
    expect(
      activityForYouHeaderCount(
        offersState: base.copyWith(totalCount: 99, hasMore: false),
        visiblePinnedCount: 2,
      ),
      2,
    );
  });

  test('keeps server aggregate while another page exists', () {
    expect(
      activityForYouHeaderCount(
        offersState: base.copyWith(totalCount: 25, hasMore: true),
        visiblePinnedCount: 20,
      ),
      25,
    );
  });

  test('includes exiting motion cards in visible count', () {
    expect(
      activityForYouHeaderCount(
        offersState: base.copyWith(totalCount: 0, hasMore: false),
        visiblePinnedCount: 1,
      ),
      1,
    );
  });

  group('activityForYouPinnedZoneHasRows (#1068)', () {
    const zoneInput = (
      offersState: base,
      visiblePinnedCount: 0,
      pinnedPromptRows: false,
      collapsedInvitePrompt: false,
    );

    test('false when the pinned zone is empty', () {
      expect(
        activityForYouPinnedZoneHasRows(
          offersState: zoneInput.offersState,
          visiblePinnedCount: zoneInput.visiblePinnedCount,
          pinnedPromptRows: zoneInput.pinnedPromptRows,
          collapsedInvitePrompt: zoneInput.collapsedInvitePrompt,
        ),
        isFalse,
      );
    });

    test('true for visible offers', () {
      expect(
        activityForYouPinnedZoneHasRows(
          offersState: zoneInput.offersState,
          visiblePinnedCount: 1,
          pinnedPromptRows: false,
          collapsedInvitePrompt: false,
        ),
        isTrue,
      );
    });

    test('true while an offer is animating out', () {
      expect(
        activityForYouPinnedZoneHasRows(
          offersState: zoneInput.offersState.copyWith(items: []),
          visiblePinnedCount: 1,
          pinnedPromptRows: false,
          collapsedInvitePrompt: false,
        ),
        isTrue,
        reason: 'exitingOffers still count as pinned-zone rows',
      );
    });

    test(
      'true for pinned prompts, collapsed batch, load failure, or unseen pages',
      () {
        expect(
          activityForYouPinnedZoneHasRows(
            offersState: zoneInput.offersState,
            visiblePinnedCount: 0,
            pinnedPromptRows: true,
            collapsedInvitePrompt: false,
          ),
          isTrue,
        );
        expect(
          activityForYouPinnedZoneHasRows(
            offersState: zoneInput.offersState,
            visiblePinnedCount: 0,
            pinnedPromptRows: false,
            collapsedInvitePrompt: true,
          ),
          isTrue,
        );
        expect(
          activityForYouPinnedZoneHasRows(
            offersState: zoneInput.offersState.copyWith(pageLoadFailed: true),
            visiblePinnedCount: 0,
            pinnedPromptRows: false,
            collapsedInvitePrompt: false,
          ),
          isTrue,
        );
        expect(
          activityForYouPinnedZoneHasRows(
            offersState: zoneInput.offersState.copyWith(
              hasMore: true,
              totalCount: 3,
            ),
            visiblePinnedCount: 0,
            pinnedPromptRows: false,
            collapsedInvitePrompt: false,
          ),
          isTrue,
        );
      },
    );
  });
}
