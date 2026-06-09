import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';

void main() {
  test('inviteShareUri builds /invite path on SERVER_NAME', () {
    if (kServerName.isEmpty) return;
    final uri = inviteShareUri('Iabc123');
    expect(uri.path, '/invite/Iabc123');
    expect(uri.host, Uri.parse(kServerName).host);
    expect(uri.fragment, isEmpty);
  });
}
