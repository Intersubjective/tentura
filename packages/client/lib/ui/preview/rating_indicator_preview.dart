import '../preview.dart';
import '../widget/rating_indicator.dart';

@Preview(
  name: 'RatingIndicator (0)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleRatingIndicator0() => const RatingIndicator(score: 0);

@Preview(
  name: 'RatingIndicator (50)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleRatingIndicator50() => const RatingIndicator(score: 50);

@Preview(
  name: 'RatingIndicator (75)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleRatingIndicator75() => const RatingIndicator(score: 75);

@Preview(
  name: 'RatingIndicator (100)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleRatingIndicator100() => const RatingIndicator(score: 100);
