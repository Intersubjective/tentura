import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

/// U092 review: every relative-time label follows ONE clock, aligned to the
/// wall clock, so N labels on screen move in one frame; hidden tabs
/// (TickerMode off) do not tick.
void main() {
  // 10 s into a 30 s period: the shared clock's next tick is 20 s away.
  final clock = DateTime.utc(2026, 10, 14, 9, 0, 10);

  setUp(() => RelativeTimestampTicker.debugClock = () => clock);
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  testWidgets('tickers mounted at different times tick in the same frame', (
    tester,
  ) async {
    var firstBuilds = 0;
    var secondBuilds = 0;
    var showSecond = false;
    late StateSetter setHost;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setHost = setState;
          return Column(
            textDirection: TextDirection.ltr,
            children: [
              RelativeTimestampTicker(
                builder: (_) {
                  firstBuilds++;
                  return const SizedBox();
                },
              ),
              if (showSecond)
                RelativeTimestampTicker(
                  builder: (_) {
                    secondBuilds++;
                    return const SizedBox();
                  },
                ),
            ],
          );
        },
      ),
    );
    await tester.pump(const Duration(seconds: 7));
    setHost(() => showSecond = true);
    await tester.pump();
    firstBuilds = 0;
    secondBuilds = 0;

    // 7 s + 14 s = 21 s: past the shared tick at 20 s. A per-widget timer
    // would fire the second label only at 7 s + 30 s.
    await tester.pump(const Duration(seconds: 14));
    expect(firstBuilds, 1);
    expect(secondBuilds, 1);
  });

  testWidgets('a ticker in a hidden tab does not tick, and catches up when '
      'shown', (tester) async {
    var builds = 0;
    Widget host({required bool enabled}) => TickerMode(
      enabled: enabled,
      child: RelativeTimestampTicker(
        builder: (_) {
          builds++;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(host(enabled: false));
    builds = 0;

    await tester.pump(const Duration(seconds: 65));
    expect(builds, 0);

    await tester.pumpWidget(host(enabled: true));
    expect(builds, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(builds, 2);
  });
}
