import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/ui/bloc/realtime_status_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/realtime_status_presenter.dart';

import '../../support/test_realtime_sync.dart';

const _title = 'Pick up the keys';

const _authenticated = RealtimeConnectionStatus(
  connectionEpoch: 1,
  phase: RealtimeConnectionPhase.authenticated,
  accountId: 'U-me',
);

/// Counts how often its state is created, to prove the banner does not
/// rebuild the screen under it from scratch.
class _InitCounter extends StatefulWidget {
  const _InitCounter({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Center(child: Text('body'));
}

/// #513 (QA on 7.41.30): the offline banner sat over the app bar and hid
/// the request title. It must take its own room at the top and push the
/// screen down instead of overlaying it.
void main() {
  testWidgets('the offline banner does not cover the app-bar title', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final realtime = buildTestRealtimeSync();
    final reachability = NetworkReachability.forTesting();
    final cubit = RealtimeStatusCubit.forTesting(
      realtime.case_,
      pausedDelay: Duration.zero,
      reachability: reachability,
    );
    addTearDown(() async {
      await reachability.dispose();
      await realtime.port.dispose();
    });
    var inits = 0;
    await tester.pumpWidget(
      MediaQuery(
        // A status bar / notch inset, as on a phone.
        data: const MediaQueryData(
          size: Size(800, 600),
          padding: EdgeInsets.only(top: 24),
          viewPadding: EdgeInsets.only(top: 24),
        ),
        child: BlocProvider(
          create: (_) => cubit,
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            // Mounted where the app mounts it: around the navigator.
            builder: (context, child) => RealtimeStatusPresenter(child: child!),
            home: Scaffold(
              appBar: AppBar(title: const Text(_title)),
              body: _InitCounter(onInit: () => inits++),
            ),
          ),
        ),
      ),
    );
    realtime.port.emitStatus(_authenticated);
    await tester.pump();
    final titleTopBefore = tester.getRect(find.text(_title)).top;

    reachability.reportTransportFailure();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final banner = find.text(l10n.connectivityOfflineBanner);
    expect(banner, findsOneWidget);
    final bannerBox = tester.getRect(
      find.ancestor(of: banner, matching: find.byType(Material)).first,
    );
    final titleRect = tester.getRect(find.text(_title));
    final appBarRect = tester.getRect(find.byType(AppBar));
    expect(
      bannerBox.overlaps(titleRect),
      isFalse,
      reason: 'banner $bannerBox covers the title $titleRect',
    );
    expect(
      bannerBox.overlaps(appBarRect),
      isFalse,
      reason: 'banner $bannerBox overlays the app bar $appBarRect',
    );
    // The banner fills the status bar inset, and the app bar right below it
    // does not pad for that inset a second time.
    expect(bannerBox.top, 0);
    expect(appBarRect.top, moreOrLessEquals(bannerBox.bottom));
    expect(titleRect.top, greaterThan(titleTopBefore));

    reachability.reportSuccess();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(banner, findsNothing);
    expect(tester.getRect(find.text(_title)).top, titleTopBefore);
    // Showing and hiding the banner keeps the screen's state.
    expect(inits, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
