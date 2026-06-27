import 'dart:async';
import 'dart:convert';

import 'package:ferry/ferry.dart'
    show Link, NextLink, RequestSerializer, ResponseParser, ServerException;
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_http_link/gql_http_link.dart'
    show HttpLinkParserException, HttpLinkServerException;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'package:tentura/data/gql/tentura_v2_upload.dart';

/// Encodes V2 uploads as GraphQL multipart so the server receives both the
/// `{ filename, type }` metadata (as the GraphQL variable) and the raw bytes
/// (as multipart part `0`).
///
/// Triggered whenever any variable contains a [TenturaV2Upload]. Requests
/// without an upload are forwarded to the next link unchanged.
class V2UploadMultipartLink extends Link {
  V2UploadMultipartLink({
    required this.uri,
    required this.httpClient,
    required this.defaultHeaders,
  });

  final Uri uri;
  final http.Client httpClient;
  final Map<String, String> defaultHeaders;

  static const _parser = ResponseParser();
  static const _serializer = RequestSerializer();

  @override
  Stream<Response> request(Request request, [NextLink? forward]) async* {
    final found = _findUpload(request.variables);
    if (found == null) {
      yield* forward!(request);
      return;
    }

    final upload = found.upload;

    final newVariables = _cloneReplacing(request.variables);

    final operations = json.encode(
      _serializer.serializeRequest(
        Request(
          operation: request.operation,
          variables: newVariables,
          context: request.context,
        ),
      ),
    );

    final map = json.encode(<String, dynamic>{
      '0': ['variables.${found.path.join('.')}'],
    });

    final mediaType = upload.mimeType.trim().isEmpty
        ? MediaType('application', 'octet-stream')
        : MediaType.parse(upload.mimeType);

    final multipart = http.MultipartRequest('POST', uri)
      ..fields['operations'] = operations
      ..fields['map'] = map
      ..files.add(
        http.MultipartFile.fromBytes(
          '0',
          upload.bytes,
          contentType: mediaType,
          filename: upload.filename,
        ),
      )
      ..headers.addAll(defaultHeaders)
      ..headers.addAll(_contextHeaders(request));

    final http.Response httpResponse;
    try {
      final streamed = await httpClient.send(multipart);
      httpResponse = await http.Response.fromStream(streamed);
    } catch (e, st) {
      throw ServerException(
        originalException: e,
        originalStackTrace: st,
      );
    }

    final Response parsed;
    try {
      final body =
          json.decode(utf8.decode(httpResponse.bodyBytes))
              as Map<String, dynamic>;
      parsed = _parser.parseResponse(body);
    } catch (e, st) {
      throw HttpLinkParserException(
        originalException: e,
        originalStackTrace: st,
        response: httpResponse,
      );
    }

    if (httpResponse.statusCode >= 300 ||
        (parsed.data == null && parsed.errors == null)) {
      throw HttpLinkServerException(
        response: httpResponse,
        parsedResponse: parsed,
        statusCode: httpResponse.statusCode,
      );
    }

    yield parsed;
  }

  Map<String, String> _contextHeaders(Request request) {
    final headers = request.context.entry<HttpLinkHeaders>()?.headers;
    return {...?headers};
  }

  /// Deep-clones [value], replacing any [TenturaV2Upload] with its
  /// `{ filename, type }` metadata map (bytes intentionally omitted).
  static Object? _cloneReplacingValue(Object? value) {
    if (value is TenturaV2Upload) {
      return <String, dynamic>{
        'filename': value.filename,
        'type': value.mimeType,
      };
    }
    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k as String, _cloneReplacingValue(v)),
      );
    }
    if (value is List) {
      return value.map(_cloneReplacingValue).toList();
    }
    return value;
  }

  static Map<String, dynamic> _cloneReplacing(Map<String, dynamic> vars) =>
      (_cloneReplacingValue(vars)! as Map).cast<String, dynamic>();

  /// Finds the first [TenturaV2Upload] and its path (e.g. `['file']`).
  static _FoundUpload? _findUpload(
    Object? value, [
    List<String> path = const [],
  ]) {
    if (value is TenturaV2Upload) {
      return _FoundUpload(path: path, upload: value);
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final hit = _findUpload(entry.value, [...path, entry.key as String]);
        if (hit != null) return hit;
      }
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final hit = _findUpload(value[i], [...path, '$i']);
        if (hit != null) return hit;
      }
    }
    return null;
  }
}

class _FoundUpload {
  const _FoundUpload({required this.path, required this.upload});

  final List<String> path;
  final TenturaV2Upload upload;
}
