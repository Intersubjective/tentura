import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

/// The §9 ceiling for the desk's collapsed block: three obligation groups
/// plus one optional line, at 360 dp and 1.3x text. Measured at 262 dp; the
/// two dp of slack are rounding, not room to grow.
const double kMyWorkBlockCeiling360Scale13 = 264;

AttentionReceipt _optionalLine() => AttentionReceipt(
  id: 'optional-1',
  category: 'requestProgress',
  kind: 'roomMessagePosted',
  priority: 'normal',
  title: 'Boris',
  body: 'posted an update in the room',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 8, 4, 9),
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: 'beacon-1',
);

AttentionReceipt _obligationLine(int index) => AttentionReceipt(
  id: 'obligation-$index',
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Anna',
  body: 'Offered help with garden cleanup',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 8, 4, 14 - index),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{"beaconTitle":"Garden cleanup"}',
  surface: AttentionSurface.myWork,
  beaconId: 'beacon-1',
  requiresAction: true,
);

MyWorkCardViewModel _vm({bool reviewCta = false}) => MyWorkCardViewModel(
  beaconId: 'beacon-1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(id: 'beacon-1', title: 'Garden cleanup'),
  showReviewHelpOffersCta: reviewCta,
);

Future<void> _pumpObligationGolden(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required Brightness brightness,
  required List<AttentionReceipt> obligations,
  bool reviewCta = false,
  TextScaler? textScaler,
  required String goldenName,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final cubit = MyWorkCubit(
    userId: 'user-1',
    myWorkCase: buildTestMyWorkCase(),
  );
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: brightness == Brightness.light
          ? TenturaTheme.light()
          : TenturaTheme.dark(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler ?? TextScaler.noScaling,
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: size.width,
                  child: BlocProvider<MyWorkCubit>.value(
                    value: cubit,
                    child: MyWorkObligationBlock(
                      vm: _vm(reviewCta: reviewCta),
                      obligations: obligations,
                      onReviewHelpOffers: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$goldenName'),
  );
}

void main() {
  const width = 360.0;
  final counts = <int, String>{
    0: '0_obligations_cta',
    1: '1_obligation',
    3: '3_obligations',
    5: '5_obligations_collapsed',
  };

  for (final brightness in Brightness.values) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      for (final entry in counts.entries) {
        final count = entry.key;
        final suffix = entry.value;
        testWidgets(
          'obligation block $suffix ${brightness.name} ${locale.languageCode}',
          (tester) async {
            final obligations = List.generate(count, _obligationLine);
            final height = count == 0 ? 120.0 : 100.0 + count.clamp(0, 3) * 110;
            await _pumpObligationGolden(
              tester,
              size: Size(width, height),
              locale: locale,
              brightness: brightness,
              obligations: obligations,
              reviewCta: count == 0,
              goldenName:
                  'my_work_obligation_block_${suffix}_${brightness.name}_${locale.languageCode}_360.png',
            );
          },
          tags: 'golden',
        );
      }
    }
  }

  testWidgets('obligation block 5 collapsed text scale 1.3 en', (tester) async {
    final obligations = List.generate(5, _obligationLine);
    await _pumpObligationGolden(
      tester,
      size: const Size(width, 420),
      locale: const Locale('en'),
      brightness: Brightness.light,
      obligations: obligations,
      textScaler: TextScaler.linear(1.3),
      goldenName: 'my_work_obligation_block_5_obligations_collapsed_light_en_360_1p3.png',
    );
  },
    tags: 'golden',
  );

  // §9 — the card's active-event block has a ceiling, and mounting it on My
  // Desk must not lift it. The worst case the desk can reach while collapsed
  // is the obligation-group cap plus one optional line, at 360 dp and 1.3x.
  testWidgets('the mounted block holds the height ceiling at 360 dp / 1.3x', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(width, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cubit = MyWorkCubit(userId: 'user-1', myWorkCase: buildTestMyWorkCase());
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(width, 1200),
            textScaler: TextScaler.linear(1.3),
          ),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: BlocProvider<MyWorkCubit>.value(
                    value: cubit,
                    child: MyWorkObligationBlock(
                      key: const Key('ceiling'),
                      vm: _vm(),
                      obligations: List.generate(40, _obligationLine),
                      optionalEvents: [_optionalLine()],
                      optionalTotal: 4000,
                      onClearEvent: (_) {},
                      onRespondHelpOffer: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final height = tester.getSize(find.byKey(const Key('ceiling'))).height;
    expect(height, lessThanOrEqualTo(kMyWorkBlockCeiling360Scale13), reason: "measured $height");
    expect(height, greaterThan(0));
    // Four rows is the cap, whatever the totals say.
    expect(find.byType(AttentionMiniCard), findsNWidgets(4));
  });
}
