import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';

void main() {
  test('recognizes phantom change messages as a dedicated realtime kind', () {
    expect(
      RealtimeEntityKind.fromWire('phantom'),
      isA<RealtimeEntityKind>().having((kind) => kind.name, 'name', 'phantom'),
    );
  });
}
