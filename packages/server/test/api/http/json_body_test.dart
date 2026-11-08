import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/http/json_body.dart';

void main() {
  Request request(String body) => Request(
    'POST',
    Uri.parse('http://localhost/x'),
    body: body,
    headers: {'content-type': 'application/json'},
  );

  test('a JSON object is returned as a map', () async {
    expect(await readJsonObject(request('{"a":1,"b":"c"}')), {
      'a': 1,
      'b': 'c',
    });
  });

  for (final body in ['', 'not json', '[1]', '"s"', '1', 'null']) {
    test('null for body ${body.isEmpty ? '<empty>' : body}', () async {
      expect(await readJsonObject(request(body)), isNull);
    });
  }

  test('invalidJsonBodyResponse is the unchanged 400', () async {
    final r = invalidJsonBodyResponse();
    expect(r.statusCode, 400);
    expect(await r.readAsString(), 'invalid JSON body');
  });
}
