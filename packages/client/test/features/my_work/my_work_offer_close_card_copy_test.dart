// The close-card action's label is user copy: it names the Request or Chat,
// never the internal word beacon, and exists in both ARB files.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/help_offer_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

AttentionReceipt _offer() => AttentionReceipt(
  id: 'r1',
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Anna',
  body: 'I can sew',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: 'beacon-1',
  requiresAction: true,
  targetEntityId: 'u1',
);

/// The offerer of the obligation is listed among the Request's help offers
/// only while the offer counts ([HelpOfferStatus.active]).
MyWorkCardViewModel _vm(
  CommitmentStakeState stake,
  BeaconStatus status,
  HelpOfferStatus offerStatus,
) => MyWorkCardViewModel(
  beaconId: 'beacon-1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(
    id: 'beacon-1',
    title: 'Garden',
    status: status,
    helpOfferUsers: offerStatus == HelpOfferStatus.active
        ? const [Profile(id: 'u1', displayName: 'Anna')]
        : const [],
  ),
  stakeState: stake,
);

Future<void> _pump(
  WidgetTester tester,
  CommitmentStakeState stake,
  Locale locale,
) async {
  final attention = StubAttentionRepository();
  final cubit = MyWorkCubit(
    userId: 'user-1',
    myWorkCase: buildTestMyWorkCase(attentionRepository: attention),
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: BlocProvider<MyWorkCubit>.value(
            value: cubit,
            child: MyWorkObligationBlock(
              vm: _vm(stake, BeaconStatus.open, HelpOfferStatus.active),
              obligations: [_offer()],
              onRespondHelpOffer: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _close = find.byKey(
  const ValueKey<String>('my-work-obligation-close:r1'),
);

/// The ARB key that holds [value] in [file], or null.
String? _keyOf(String file, String value) {
  final arb = jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
  for (final e in arb.entries) {
    if (!e.key.startsWith('@') && e.value == value) return e.key;
  }
  return null;
}

void main() {
  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets('the close-card label in ${locale.languageCode} names the '
        'Request or Chat and is an ARB string in both locales', (tester) async {
      await _pump(tester, CommitmentStakeState.acknowledged, locale);

      final label = find.descendant(of: _close, matching: find.byType(Text));
      expect(label, findsWidgets);
      final text = tester.widget<Text>(label.first).data ?? '';
      expect(text.toLowerCase(), isNot(contains('beacon')));
      expect(text.toLowerCase(), isNot(contains('маяк')));
      expect(
        text.toLowerCase(),
        matches(
          locale.languageCode == 'ru'
              ? RegExp('запрос|чат')
              : RegExp('request|chat'),
        ),
      );
      final key = _keyOf('l10n/app_${locale.languageCode}.arb', text);
      expect(key, isNotNull);
      final other = locale.languageCode == 'ru' ? 'en' : 'ru';
      final otherArb =
          jsonDecode(File('l10n/app_$other.arb').readAsStringSync())
              as Map<String, dynamic>;
      expect(otherArb[key], isA<String>());
    });
  }
}
