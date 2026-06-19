import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';

void main() {
  test('kMyWorkFilterMenuOrder matches product menu sequence', () {
    expect(
      kMyWorkFilterMenuOrder,
      [
        MyWorkFilter.active,
        MyWorkFilter.authored,
        MyWorkFilter.helpOffered,
        MyWorkFilter.drafts,
        MyWorkFilter.all,
        MyWorkFilter.archived,
      ],
    );
    expect(kMyWorkFilterMenuOrder.length, MyWorkFilter.values.length);
  });
}
