import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/profile_view/data/repository/mutual_friends_repository.dart';
import 'package:tentura/features/profile_view/ui/widget/mutual_friends_button.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_dispatcher.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../support/phone_surface.dart';
import '../support/remote_wire_harness.dart';

// Error effects resolve the router, but displaying the error never uses it.
class _UnusedNavigator extends Mock implements AppNavigator {}

void main() {
  setUp(() {
    GetIt.I.registerSingleton<AppNavigator>(_UnusedNavigator());
    GetIt.I.registerSingleton<Logger>(Logger('generic-error-snackbar'));
  });

  tearDown(GetIt.I.reset);

  testWidgets(
    'Russian generic error shows its controls without overflow on a phone at text scale 1.0',
    (tester) async {
      await usePhoneSurface(tester);
      final l10n = lookupL10n(const Locale('ru'));
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          // The original 375x667 RU run used the default 1.0 text scale.
          // Keep it explicit so ambient accessibility settings cannot alter it.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => dispatchUiEffect(
                    context,
                    ShowError(StateError('Unexpected server response')),
                  ),
                  child: const Text('Показать ошибку'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Scaffold)), const Size(375, 667));
      await tester.tap(find.text('Показать ошибку'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final snackbar = find.byType(SnackBar);
      expect(snackbar, findsOneWidget);
      final message = find.descendant(
        of: snackbar,
        matching: find.text(l10n.errorGenericAction, findRichText: true),
      );
      final copy = find.descendant(
        of: snackbar,
        matching: find.text(l10n.copyErrorDetails),
      );
      final close = find.descendant(
        of: snackbar,
        matching: find.byIcon(Icons.close),
      );
      expect(message, findsOneWidget);
      expect(copy, findsOneWidget);
      expect(close, findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'Displaying the Russian generic error and its controls must not '
            'produce a RenderFlex overflow.',
      );
    },
  );

  testWidgets(
    'Failed mutual friends request shows Russian error controls without overflow on a phone',
    (tester) async {
      await usePhoneSurface(tester);
      final l10n = lookupL10n(const Locale('ru'));
      final sent = <WireSent>[];
      // This production widget calls its repository directly; there is no
      // cubit in this path. Only HTTP is faked, using the real Ferry error
      // handling, repository, widget catch block and snackbar layout.
      await tester.runAsync(
        () => withRemoteWire(
          {},
          sent,
          (remote) async {
            GetIt.I.registerSingleton<MutualFriendsRepository>(
              MutualFriendsRepository(remote),
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: TenturaTheme.light(),
                locale: const Locale('ru'),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.noScaling,
                  ),
                  child: child!,
                ),
                home: const Scaffold(
                  body: MutualFriendsButton(userId: 'Ufriend000001'),
                ),
              ),
            );
            expect(tester.getSize(find.byType(Scaffold)), const Size(375, 667));
            expect(find.byType(SnackBar), findsNothing);
            await tester.tap(find.text(l10n.showMutualFriends));
            for (
              var i = 0;
              i < 40 && find.byType(SnackBar).evaluate().isEmpty;
              i++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
              await tester.pump(const Duration(milliseconds: 25));
            }
            await tester.pump(const Duration(milliseconds: 300));

            expect(sent, hasLength(1));
            expect(sent.single.operationName, 'MutualFriendsFetch');
            expect(sent.single.variables['id'], 'Ufriend000001');
            final snackbar = find.byType(SnackBar);
            expect(snackbar, findsOneWidget);
            expect(
              find.descendant(
                of: snackbar,
                matching: find.text(
                  l10n.errorGenericAction,
                  findRichText: true,
                ),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: snackbar,
                matching: find.text(l10n.copyErrorDetails),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: snackbar,
                matching: find.byIcon(Icons.close),
              ),
              findsOneWidget,
            );
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'A real failed request must display the Russian generic '
                  'error without a RenderFlex overflow at 375x667.',
            );
          },
          errors: const {
            'MutualFriendsFetch': {
              'message': 'Unexpected server response',
            },
          },
        ),
      );
    },
  );
}
