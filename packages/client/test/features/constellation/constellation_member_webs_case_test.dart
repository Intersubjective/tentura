import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_member_webs_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_member_webs_case.dart';

class _MemberWebsPort implements ConstellationMemberWebsPort {
  final requestedIds = <String>[];
  Future<List<ConstellationMemberWeb>> Function(String) response = (_) async =>
      const [];

  @override
  Future<List<ConstellationMemberWeb>> fetch(String beaconId) {
    requestedIds.add(beaconId);
    return response(beaconId);
  }
}

void main() {
  group('Constellation member webs use case', () {
    late _MemberWebsPort port;
    late ConstellationMemberWebsCase memberWebsCase;

    setUp(() {
      port = _MemberWebsPort();
      memberWebsCase = ConstellationMemberWebsCase(
        port,
        env: const Env(),
        logger: Logger('test'),
      );
    });

    test(
      'fetches the selected request and preserves all member states',
      () async {
        const webs = [
          ConstellationMemberWeb(
            beaconId: 'request-a',
            personId: 'person-forwarded',
            state: ConstellationMemberWebState.forwarded,
          ),
          ConstellationMemberWeb(
            beaconId: 'request-a',
            personId: 'person-inside',
            state: ConstellationMemberWebState.inside,
          ),
        ];
        port.response = (_) async => webs;

        expect(await memberWebsCase.fetch('request-a'), orderedEquals(webs));
        expect(port.requestedIds, ['request-a']);
      },
    );

    test(
      'delegates each fetch to the port including empty member webs',
      () async {
        expect(await memberWebsCase.fetch('request-a'), isEmpty);
        expect(await memberWebsCase.fetch('request-b'), isEmpty);
        expect(port.requestedIds, ['request-a', 'request-b']);
      },
    );

    test('propagates the original port failure without retrying', () async {
      final failure = StateError('request is no longer visible');
      port.response = (_) async => throw failure;

      await expectLater(
        memberWebsCase.fetch('request-a'),
        throwsA(same(failure)),
      );
      expect(port.requestedIds, ['request-a']);
    });
  });
}
