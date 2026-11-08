import 'package:shelf_plus/shelf_plus.dart';

/// Reads [request]'s body as a JSON object; null when it is not valid JSON
/// or not an object.
Future<Map<String, dynamic>?> readJsonObject(Request request) async {
  try {
    return (await request.body.asJson as Map).cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}

/// The 400 returned when [readJsonObject] yields null.
Response invalidJsonBodyResponse() =>
    Response.badRequest(body: 'invalid JSON body');
