import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/seen_ack_case.dart';

void main() {
  const case_ = SeenAckCase();

  AttentionVisibilityEvidence evidence({
    double visibleFraction = 0.6,
    Duration visibleFor = const Duration(milliseconds: 800),
    bool appIsFocused = true,
    bool routeIsCurrent = true,
  }) => AttentionVisibilityEvidence(
    visibleFraction: visibleFraction,
    visibleFor: visibleFor,
    appIsFocused: appIsFocused,
    routeIsCurrent: routeIsCurrent,
  );

  test('acknowledges only focused current-route dwell evidence', () {
    expect(case_.shouldAcknowledge(evidence()), isTrue);
    expect(case_.shouldAcknowledge(evidence(visibleFraction: 0.59)), isFalse);
    expect(
      case_.shouldAcknowledge(
        evidence(visibleFor: const Duration(milliseconds: 799)),
      ),
      isFalse,
    );
    expect(case_.shouldAcknowledge(evidence(appIsFocused: false)), isFalse);
    expect(case_.shouldAcknowledge(evidence(routeIsCurrent: false)), isFalse);
  });
}
