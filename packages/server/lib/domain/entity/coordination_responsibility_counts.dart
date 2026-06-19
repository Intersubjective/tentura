/// Per-beacon responsibility counts for the YOU line (server domain).
class CoordinationResponsibilityCounts {
  const CoordinationResponsibilityCounts({
    required this.beaconId,
    this.askOpen = 0,
    this.askNew = 0,
    this.promiseOpen = 0,
    this.promiseNew = 0,
    this.blockerOpen = 0,
    this.blockerNew = 0,
    this.reviewOpen = 0,
    this.reviewNew = 0,
    this.othersOpenCount = 0,
  });

  final String beaconId;
  final int askOpen;
  final int askNew;
  final int promiseOpen;
  final int promiseNew;
  final int blockerOpen;
  final int blockerNew;
  final int reviewOpen;
  final int reviewNew;
  final int othersOpenCount;

  int get totalOpen => askOpen + promiseOpen + blockerOpen + reviewOpen;

  int get totalNew => askNew + promiseNew + blockerNew + reviewNew;

  bool get hasAny => totalOpen > 0;
}
