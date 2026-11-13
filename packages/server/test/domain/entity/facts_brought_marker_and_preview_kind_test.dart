import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_thread_record.dart';

void main() {
  group('facts-brought chat line', () {
    test('uses semantic marker 20', () {
      expect(BeaconRoomSemanticMarker.factsBrought, 20);
    });

    test('previews as its own kind, distinct from every existing kind', () {
      final existing = <int>{
        ThreadMessagePreviewKind.text,
        ThreadMessagePreviewKind.attachment,
        ThreadMessagePreviewKind.planUpdated,
        ThreadMessagePreviewKind.factPinned,
        ThreadMessagePreviewKind.participantStatus,
        ThreadMessagePreviewKind.coordination,
        ThreadMessagePreviewKind.needInfo,
        ThreadMessagePreviewKind.done,
        ThreadMessagePreviewKind.poll,
        ThreadMessagePreviewKind.join,
        ThreadMessagePreviewKind.factEdited,
        ThreadMessagePreviewKind.factUnpinned,
        ThreadMessagePreviewKind.factQuoted,
      };
      expect(existing, hasLength(13));
      expect(existing, isNot(contains(ThreadMessagePreviewKind.factsBrought)));
    });
  });
}
