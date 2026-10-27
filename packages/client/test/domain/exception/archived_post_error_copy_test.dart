import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_dispatcher.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';

class _UnusedRootRouter extends Mock implements RootRouter {}

class _UnusedBeaconRepository extends Mock implements BeaconRepository {}

class _RealtimeSync extends Mock implements RealtimeSyncPort {
  @override
  Stream<RealtimeEntityChange> get entityChanges => const Stream.empty();
}

void main() {
  group(
    'Archived Post refusals show localized copy for forwarding and invitations',
    () {
      setUp(() {
        GetIt.I
          ..registerSingleton<RootRouter>(_UnusedRootRouter())
          ..registerSingleton<Logger>(Logger('ArchivedPostErrorCopyTest'));
      });
      tearDown(GetIt.I.reset);

      for (final operation in ['ForwardBeacon', 'InvitationCreate']) {
        for (final (locale, expected) in [
          ('en', 'This post is archived'),
          ('ru', 'Пост в архиве'),
        ]) {
          testWidgets(
            '$operation displays the archived Post message in $locale',
            (
              tester,
            ) async {
              // Exercise the production repository and GraphQL error link. Code
              // 1332 currently becomes a typed PostNotOpenException before the
              // generic RemoteApiException mapping is reached.
              final sent = <WireSent>[];
              final error = await tester.runAsync<Object>(() async {
                Object? failure;
                await withRemoteWire(const {}, sent, (remote) async {
                  final forwards = ForwardRepository(
                    remote,
                    _UnusedBeaconRepository(),
                    _RealtimeSync(),
                  );
                  final invitations = InvitationRepository(remote);
                  try {
                    if (operation == 'ForwardBeacon') {
                      await forwards.forwardBeacon(
                        beaconId: 'Bpost00000001',
                        recipientIds: ['Urecipient001'],
                      );
                    } else {
                      await invitations.create(
                        addresseeName: 'Friend',
                        beaconId: 'Bpost00000001',
                      );
                    }
                  } catch (error) {
                    failure = error;
                  } finally {
                    await forwards.dispose();
                    await invitations.dispose();
                  }
                }, errors: {operation: wireCodeError(1332)});
                expect(sent.single.operationName, operation);
                expect(
                  failure,
                  isA<PostNotOpenException>(),
                  reason:
                      'The repository must preserve the archived Post refusal',
                );
                return failure!;
              });
              expect(error, isA<PostNotOpenException>());

              await tester.pumpWidget(
                MaterialApp(
                  theme: TenturaTheme.light(),
                  locale: Locale(locale),
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => dispatchUiEffect(
                          context,
                          ShowError(error!),
                          localeName: locale,
                        ),
                        child: const Text('Show error'),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Show error'));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));

              expect(find.text(expected, findRichText: true), findsOneWidget);
              expect(
                find.textContaining('PostNotOpenException', findRichText: true),
                findsNothing,
              );
            },
          );
        }
      }
    },
  );
}
