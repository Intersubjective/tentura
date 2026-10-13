import 'package:tentura_server/data/service/main_db_scope_admission.dart';
import 'package:test/test.dart';

void main() {
  late MainDbScopeAdmission admission;

  setUp(() => admission = MainDbScopeAdmission(maxConcurrent: 4));
  tearDown(() => admission.close());

  test(
    'an admitted body can not take a second slot of the same admission',
    () async {
      // Spare capacity exists: the guard must reject re-entry itself, not rely
      // on the queue running dry.
      await expectLater(
        admission.run(() => admission.run(() async => 1)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('admission'), contains('re-entr')),
          ),
        ),
      );
    },
  );

  test('re-entry is rejected for every work kind', () async {
    for (final kind in MainDbWorkKind.values) {
      await expectLater(
        admission.run(() => admission.run(() async => 1, kind: kind)),
        throwsA(isA<StateError>()),
        reason: kind.name,
      );
    }
  });

  test('sequential and sibling admissions are still allowed', () async {
    expect(await admission.run(() async => 1), 1);
    final both = await Future.wait([
      admission.run(() async => 2),
      admission.run(() async => 3),
    ]);
    expect(both, [2, 3]);
    expect(admission.running, 0);
  });

  test('a guarded re-entry attempt releases the outer slot', () async {
    await admission
        .run(() => admission.run(() async => 1))
        .then<void>((_) {}, onError: (_) {});
    expect(admission.running, 0);
  });
}
