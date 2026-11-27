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

  test('serverAbsoluteUri puts a server-relative invite link on the origin', () {
    final uri = serverAbsoluteUri(
      '/invite/Iabc123?r=Bxyz',
      base: 'https://app.example.org',
    );
    expect(uri.toString(), 'https://app.example.org/invite/Iabc123?r=Bxyz');
    expect(uri.hasScheme, isTrue);
  });
}
