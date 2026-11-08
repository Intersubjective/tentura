import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:injectable/injectable.dart' show Environment;

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/offer_accepted_dismissal_repository_port.dart';
import 'package:tentura_server/domain/use_case/offer_accepted_dismissal_case.dart';
import 'package:tentura_server/env.dart';

/// Only users in [helpersByBeacon] may dismiss; dismissals are kept in order.
final class _FakeDismissals implements OfferAcceptedDismissalRepositoryPort {
  final helpersByBeacon = <String, Set<String>>{};
  final dismissed = <String, List<String>>{};
  int listReads = 0;

  @override
  Future<bool> dismiss({
    required String userId,
    required String beaconId,
  }) async {
    if (!(helpersByBeacon[beaconId]?.contains(userId) ?? false)) return false;
    final list = dismissed[userId] ??= [];
    if (!list.contains(beaconId)) list.add(beaconId);
    return true;
  }

  @override
  Future<List<String>> dismissedBeaconIds({required String userId}) async {
    listReads++;
    return List.of(dismissed[userId] ?? const []);
  }
}

void main() {
  late _FakeDismissals dismissals;
  late OfferAcceptedDismissalCase case_;

  setUp(() {
    dismissals = _FakeDismissals()
      ..helpersByBeacon['B1'] = {'Uhelper'}
      ..helpersByBeacon['B2'] = {'Uhelper'};
    case_ = OfferAcceptedDismissalCase(
      dismissals,
      env: Env(environment: Environment.test),
      logger: Logger('OfferAcceptedDismissalCaseTest'),
    );
  });

  test('list is the account-wide dismissals, empty at first', () async {
    expect(await case_.list(userId: 'Uhelper'), {
      'userId': 'Uhelper',
      'beaconIds': <String>[],
    });
  });

  test('dismiss stores and answers the whole list, oldest first', () async {
    await case_.dismiss(beaconId: 'B2', userId: 'Uhelper');
    final result = await case_.dismiss(beaconId: 'B1', userId: 'Uhelper');

    expect(result, {
      'userId': 'Uhelper',
      'beaconIds': ['B2', 'B1'],
    });
  });

  test('dismiss is idempotent', () async {
    await case_.dismiss(beaconId: 'B1', userId: 'Uhelper');
    final result = await case_.dismiss(beaconId: 'B1', userId: 'Uhelper');
    expect(result['beaconIds'], ['B1']);
  });

  test(
    'someone without an offer there is refused and nothing is read',
    () async {
      await expectLater(
        case_.dismiss(beaconId: 'B1', userId: 'Ustranger'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(dismissals.dismissed, isEmpty);
      expect(dismissals.listReads, 0);
    },
  );
}
