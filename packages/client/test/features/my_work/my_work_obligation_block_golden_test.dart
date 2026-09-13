import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

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
            final height = count == 0 ? 120.0 : 80.0 + count.clamp(0, 3) * 36;
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
        );
      }
    }
  }

  testWidgets('obligation block 5 collapsed text scale 1.3 en', (tester) async {
    final obligations = List.generate(5, _obligationLine);
    await _pumpObligationGolden(
      tester,
      size: const Size(width, 200),
      locale: const Locale('en'),
      brightness: Brightness.light,
      obligations: obligations,
      textScaler: TextScaler.linear(1.3),
      goldenName: 'my_work_obligation_block_5_obligations_collapsed_light_en_360_1p3.png',
    );
  });
}
