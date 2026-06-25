import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';

void main() {
  test('inviteShareUri builds /invite path on SERVER_NAME', () {
    final uri = inviteShareUri('Iabc123');
    expect(uri.path, '/invite/Iabc123');
    expect(uri.fragment, isEmpty);
    if (kServerName.isNotEmpty) {
      expect(uri.host, Uri.parse(kServerName).host);
    }
  });
}
