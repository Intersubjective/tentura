import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

/// Request bodies every controller that reads its JSON body through
/// `readJsonObject` must reject: not valid JSON, and valid JSON that is not
/// an object.
const kInvalidJsonBodies = <String, String>{
  'a body that is not JSON': 'not json',
  'an empty body': '',
  'a JSON array': '[1]',
  'a JSON string': '"x"',
  'JSON null': 'null',
};

/// The answer those controllers gave on main before `readJsonObject`
/// (4f40b9652: `Response.badRequest(body: 'invalid JSON body')` inline in
/// each controller): status 400, the body `invalid JSON body`, and the same
/// headers that expression yields (no content-type of its own; the server
/// adapter adds its default when serving).
Future<void> expectInvalidJsonBody400(Response response) async {
  final preRefactor = Response.badRequest(body: 'invalid JSON body');
  expect(response.statusCode, 400);
  expect(response.headers, preRefactor.headers);
  expect(response.headers['content-type'], isNull);
  expect(await response.readAsString(), 'invalid JSON body');
}
