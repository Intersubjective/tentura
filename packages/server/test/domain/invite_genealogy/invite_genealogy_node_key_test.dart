import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/env.dart';

void main() {
  final env = Env(
    environment: Environment.test,
    genealogyNodeKeySecret: 'test-genealogy-secret',
  );

  test('derive is stable and opaque', () {
    final a = InviteGenealogyNodeKey.derive(userId: 'Uabc123456789', env: env);
    final b = InviteGenealogyNodeKey.derive(userId: 'Uabc123456789', env: env);
    expect(a, b);
    expect(a.startsWith('G'), isTrue);
    expect(a.contains('Uabc'), isFalse);
  });

  test('derive differs per user id', () {
    final a = InviteGenealogyNodeKey.derive(userId: 'Uabc123456789', env: env);
    final b = InviteGenealogyNodeKey.derive(userId: 'Uxyz123456789', env: env);
    expect(a, isNot(b));
  });
}
