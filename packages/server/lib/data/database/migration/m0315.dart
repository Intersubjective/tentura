part of '_migrations.dart';

/// Settles live «new help offer» obligations left behind by offers admitted
/// before the author-side settle existed, and by withdrawn or missing offers.
/// Same rule as reconcile, for every account; a rerun changes nothing.
final m0315 = Migration('0315', [
  HelpOfferSettlementSql.settleStale(accountScope: 'TRUE'),
]);
