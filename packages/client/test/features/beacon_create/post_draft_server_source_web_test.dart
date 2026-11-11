@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';

import 'post_draft_server_autosave_wire_test.dart' as harness;

void main() {
  testWidgets(
    'opening a server Post draft ignores obsolete session text and restores its saved settings',
    (tester) async {
      // This is the actual _storageKey from the legacy web store. Keep this
      // literal after the obsolete implementation is deleted.
      const key = 'tentura_post_create_composer';
      const staleBody = 'obsolete browser-only text';
      web.window.sessionStorage.setItem(
        key,
        jsonEncode({
          'draftId': 'Bpostdraft001',
          'body': staleBody,
        }),
      );
      expect(
        jsonDecode(web.window.sessionStorage.getItem(key)!),
        containsPair('body', staleBody),
      );
      addTearDown(() => web.window.sessionStorage.removeItem(key));

      String? serverBody;
      String? composerBody;
      Map<String, Object?>? restored;
      List<Map<String, dynamic>>? reads;
      await harness.withServerPostComposer(
        tester,
        (cubit, forward, wire) async {
          serverBody = cubit.state.description;
          composerBody = tester
              .widget<TextField>(find.byKey(PostCreateScreen.textFieldKey))
              .controller!
              .text;
          reads = wire
              .calls('BeaconFetchById')
              .map((call) => call.variables)
              .toList();
          final picker = find.byType(SegmentedButton<int>);
          await Scrollable.ensureVisible(
            tester.element(picker),
            alignment: 0.5,
          );
          await tester.pump();
          final lifetime = tester.widget<SegmentedButton<int>>(picker).selected;
          final toggle = find.byType(SwitchListTile);
          if (toggle.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              toggle,
              120,
              scrollable: find.byType(Scrollable).first,
              maxScrolls: 12,
            );
          }
          await Scrollable.ensureVisible(
            tester.element(toggle),
            alignment: 0.5,
          );
          await tester.pump();
          restored = {
            'body': composerBody,
            'forwardable': tester.widget<SwitchListTile>(toggle).value,
            'lifetime': lifetime,
          };
        },
        policy: 0,
        lifetimeHours: 6,
        restoreAttachments: true,
        loadAfterMount: true,
      );
      final frameworkError = tester.takeException();
      // Package-test teardown reports values even when the Flutter web runner
      // collapses widget failures to "See exception logs".
      addTearDown(() {
        expect(
          frameworkError,
          isNull,
          reason: 'the browser harness reached the real composer',
        );
        expect(reads, isNotEmpty);
        expect(
          reads!.every((vars) => vars['id'] == 'Bpostdraft001'),
          isTrue,
          reason: 'the draft came through BeaconFetchById, not browser storage',
        );
        expect(serverBody, 'hello');
        expect(composerBody, isNot(staleBody));
        expect(restored, {
          'body': 'hello',
          'forwardable': false,
          'lifetime': {6},
        });
      });
    },
  );
}
