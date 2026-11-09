import 'package:test/test.dart';

import 'package:tentura_server/data/repository/mock/witness_window_repository_mock.dart';
import 'package:tentura_server/domain/policy/witness_window_invalidation.dart';

final class _RecordingWitnessWindow extends WitnessWindowRepositoryMock {
  final invalidated = <String>[];

  @override
  Future<void> invalidateFor({required String userId}) async =>
      invalidated.add(userId);
}

void main() {
  test('invalidates the first user, then the second', () async {
    final witnessWindow = _RecordingWitnessWindow();

    await invalidateWitnessWindowsForPair(witnessWindow, 'U-a', 'U-b');

    expect(witnessWindow.invalidated, ['U-a', 'U-b']);
  });

  test('a null witness window is a no-op', () async {
    await expectLater(
      invalidateWitnessWindowsForPair(null, 'U-a', 'U-b'),
      completes,
    );
  });
}
