import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/rating/data/gql/_g/rating_fetch.data.gql.dart';
import 'package:tentura/features/rating/data/repository/rating_repository.dart';

void main() {
  group('RatingRepository.profilesFromRows', () {
    test('skips MeritRank rows whose user relationship is null', () {
      final beaconRow = GRatingFetchData_rating(
        (b) => b
          ..src_score = 12
          ..dst_score = 34,
      );

      expect(beaconRow.user, isNull);
      expect(RatingRepository.profilesFromRows([beaconRow]), isEmpty);
    });
  });
}
