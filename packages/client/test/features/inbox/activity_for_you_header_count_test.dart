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
}
