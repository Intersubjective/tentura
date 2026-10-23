// #415 (QA r8pr3 residual): in the Message actions sheet, Tab moved
// Flutter's focus through the reactions, but the browser's focus stayed on
// one sheet-sized node, so a screen reader never heard which reaction was
// focused. Each reaction names itself with an outer
// `Semantics(label: ..., excludeSemantics: true)`, which also hid its focus
// state.
//
// Spec: every reaction is one Tab stop that puts the focus on a node of its
// own, named by the reaction's meaning.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/reaction_quick_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../../support/a11y_tab_walk.dart';

const _before = 'Control before';
const _after = 'Control after';

void main() {
  final l10n = L10nEn();

  testWidgets(
    '#415 Message actions reactions: each Tab moves the browser focus',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          // Built inside the test body: desktop platform, as on the web.
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(onPressed: () {}, child: const Text(_before)),
                  ReactionQuickPicker(selected: const {}, onPick: (_) {}),
                  ElevatedButton(onPressed: () {}, child: const Text(_after)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stops = await walkTabStops(tester, before: _before, after: _after);
      const emojis = BeaconRoomMessageReaction.quickPickerEmojis;
      expect(stops, hasLength(emojis.length + 1), reason: '$stops');
      for (var i = 0; i < emojis.length; i++) {
        expect(
          stops[i],
          contains(reactionEmojiMeaning(l10n, emojis[i])),
          reason: '$stops',
        );
      }
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
