// MIME decoding and the image picker platform are test-only I/O seams.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mime/mime.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';

import '../../../support/constellation_field_wire_fixture.dart';

const avatarViewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const accountHolderId = 'Uanna00000001';
const otherAccountHolderId = 'Ualex00000001';
const accountlessId = 'PH0123456789ab';
const accountlessEmoji = '🌻';
const accountlessName = 'Amira';
const invitedCode = 'I123456789abc';
const _downloadPath = '/api/v2/private-avatars';
const _publicImageId = 'public-face';

final avatarFixtureTime = DateTime.utc(2026, 11, 24, 12);

typedef AvatarWireCall = ({
  String field,
  bool isMutation,
  String path,
  Map<String, Object?> variables,
  List<int>? file,
});

class PrivateAvatarWire {
  PrivateAvatarWire({
    Iterable<String> savedAvatars = const [],
    this.emoji = accountlessEmoji,
    this.accountlessDisplayName = accountlessName,
    this.contacts = const {
      accountHolderId: 'Anna',
      otherAccountHolderId: 'Alex',
    },
    this.responseFor,
    bool pauseUploadResponse = false,
  }) : _seedPhotos = {
         for (final (index, id) in savedAvatars.indexed)
           id: _photoJpeg(20 + index * 30),
       },
       _picker = _JpegPicker(_photoJpeg(170)),
       _uploadResponseGate = pauseUploadResponse ? Completer<void>() : null {
    _privatePhotos.addAll(_seedPhotos);
  }

  final String? emoji;
  final String accountlessDisplayName;
  final Map<String, String> contacts;

  /// Overrides the payload for calls the scenario handles. Null uses the
  /// ordinary Field or avatar fixture response.
  final FutureOr<Object?> Function(AvatarWireCall)? responseFor;
  final _JpegPicker _picker;
  final Completer<void>? _uploadResponseGate;
  final calls = <AvatarWireCall>[];
  final returnedAvatarFlags = <Map<String, bool>>[];
  final downloads = <Uri>[];
  final _newPeople = <String, Map<String, Object?>>{};
  final _invited = <String>{};
  final Map<String, List<int>> _seedPhotos;
  final _privatePhotos = <String, List<int>>{};
  final _publicPhoto = img.encodeJpg(img.Image(width: 4, height: 8));

  List<AvatarWireCall> get uploads =>
      calls.where((call) => call.field == 'personPrivateAvatarUpload').toList();

  List<String> get createdIds => _newPeople.keys.toList();
  List<int> get pickedBytes => _picker.bytes;
  int get picks => _picker.picks;

  List<int> expectedPhotoBytes(String id) => _seedPhotos[id] ?? pickedBytes;

  void releaseUploadResponse() => _uploadResponseGate?.complete();

  String publicUrl(String id) =>
      serverImageUrl(authorId: id, imageId: _publicImageId);

  Future<void> run(Future<void> Function(RemoteApiService) body) async {
    final originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _picker;
    final originalImageClient = debugNetworkImageHttpClientProvider;
    debugNetworkImageHttpClientProvider = () => _ImageClient(this);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    try {
      await http.runWithClient(
        () async {
          final remote = RemoteApiService(
            const Env(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          try {
            await remote.setSessionAuth();
            await body(remote);
          } finally {
            await remote.close();
          }
        },
        () => MockClient.streaming(_respond),
      );
    } finally {
      ImagePickerPlatform.instance = originalPicker;
      debugNetworkImageHttpClientProvider = originalImageClient;
    }
  }

  String _objectKey(String id) => 'private/${avatarViewer.id}/$id.jpg';

  bool isPrivateUrl(Uri uri, String id) =>
      uri.path == _downloadPath &&
      (uri.queryParameters['objectKey'] == _objectKey(id) ||
          uri.queryParameters['subjectUserId'] == id ||
          uri.queryParameters['subjectPhantomId'] == id);

  List<int>? imageAt(Uri uri) {
    if (uri.path == _downloadPath) {
      for (final entry in _privatePhotos.entries) {
        if (isPrivateUrl(uri, entry.key)) {
          downloads.add(uri);
          return entry.value;
        }
      }
      return null;
    }
    if ([accountHolderId, otherAccountHolderId].any(
      (id) => Uri.parse(publicUrl(id)) == uri,
    )) {
      return _publicPhoto;
    }
    return null;
  }

  Future<http.StreamedResponse> _respond(
    http.BaseRequest request,
    Stream<List<int>> body,
  ) async {
    final uri = request.url;
    if (uri.path == _downloadPath && request.method == 'DELETE') {
      await body.drain<void>();
      final id = _privatePhotos.keys
          .where((id) => isPrivateUrl(uri, id))
          .singleOrNull;
      if (id != null) _privatePhotos.remove(id);
      return http.StreamedResponse(
        const Stream.empty(),
        id == null ? 404 : 204,
      );
    }
    if (request.method == 'GET') {
      final bytes = imageAt(uri);
      return http.StreamedResponse(
        Stream.value(bytes ?? const []),
        bytes == null ? 404 : 200,
        headers: {'content-type': 'image/jpeg'},
      );
    }
    if (uri.path.endsWith('/session/access-token')) {
      await body.drain<void>();
      return _json({
        'subject': avatarViewer.id,
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }

    final contentType = MediaType.parse(request.headers['content-type']!);
    final operations = <String, Object?>{};
    List<int>? bytes;
    if (contentType.mimeType == 'multipart/form-data') {
      final parts = <String, List<int>>{};
      await for (final part in MimeMultipartTransformer(
        contentType.parameters['boundary']!,
      ).bind(body)) {
        final name = RegExp(
          r'\bname="([^"]+)"',
        ).firstMatch(part.headers['content-disposition']!)!.group(1)!;
        parts[name] = await part.expand((chunk) => chunk).toList();
      }
      operations.addAll(_decode(utf8.decode(parts['operations']!)));
      final mapping = _decode(utf8.decode(parts['map']!));
      final filePart = mapping.entries.singleWhere(
        (part) => (part.value! as List<Object?>).contains('variables.file'),
      );
      bytes = parts[filePart.key];
    } else {
      operations.addAll(_decode(await utf8.decoder.bind(body).join()));
    }

    final document = parseString(operations['query']! as String);
    final operation = document.definitions
        .whereType<OperationDefinitionNode>()
        .singleWhere(
          (operation) => operation.name?.value == operations['operationName'],
        );
    final root = operation.selectionSet.selections
        .whereType<FieldNode>()
        .singleWhere((field) => field.name.value != '__typename');
    final call = (
      field: root.name.value,
      isMutation: operation.type == OperationType.mutation,
      path: uri.path,
      variables: (operations['variables'] as Map<String, Object?>?) ?? {},
      file: bytes,
    );
    calls.add(call);
    if (call.field == 'personPrivateAvatarUpload') {
      await _uploadResponseGate?.future;
    }
    final respond = responseFor;
    final override = respond == null ? null : await respond(call);
    final payload = override ?? _payload(call, root, document);
    return _json({
      'data': {
        '__typename': call.isMutation ? 'mutation_root' : 'query_root',
        root.alias?.value ?? root.name.value: payload,
      },
    });
  }

  Object _payload(AvatarWireCall call, FieldNode root, DocumentNode document) {
    final variables = call.variables;
    switch (call.field) {
      case 'constellationField':
        return _snapshot(root, document);
      case 'personNote':
      case 'personNoteSearch':
        return <Object?>[];
      case 'fieldSearch':
        return {
          '__typename': 'v2_FieldSearchResult',
          'people': [
            if ((variables['query']! as String).toLowerCase() == 'anna')
              {
                '__typename': 'v2_FieldSearchPerson',
                'id': accountHolderId,
                'displayName': 'Anna',
              },
          ],
          'requests': <Object?>[],
          'posts': <Object?>[],
        };
      case 'phantomCreate':
        final id = 'PH${(_newPeople.length + 2).toString().padLeft(12, '0')}';
        _newPeople[id] = variables;
        return id;
      case 'phantomInviteEnsure':
        final id = variables['id']! as String;
        expect(_newPeople, contains(id));
        _invited.add(id);
        return invitedCode;
      case 'personPrivateAvatarUpload':
        final id = _subjectOf(call);
        expect(call.path, '/api/v2/graphql');
        expect(call.file, isNotNull, reason: 'the JPEG is a multipart file');
        _privatePhotos[id] = call.file!;
        return true;
      case 'personPrivateAvatarDelete':
      case 'personPrivateAvatarRemove':
        final key = variables['objectKey'] as String?;
        final id = key == null
            ? _subjectOf(call)
            : _privatePhotos.keys
                  .where((id) => _objectKey(id) == key)
                  .singleOrNull;
        return _privatePhotos.remove(id) != null;
      default:
        throw StateError('Unexpected GraphQL field ${call.field}');
    }
  }

  String _subjectOf(AvatarWireCall call) {
    final user = call.variables['subjectUserId'] as String?;
    final accountless = call.variables['subjectPhantomId'] as String?;
    expect([?user, ?accountless], hasLength(1));
    if (user != null) return user;
    expect([accountlessId, ...createdIds], contains(accountless));
    return accountless!;
  }

  Map<String, Object?> _snapshot(FieldNode root, DocumentNode document) {
    final field =
        constellationFieldWire(
              now: avatarFixtureTime,
              viewerId: avatarViewer.id,
              contacts: contacts,
              phantoms: [
                _accountlessRow(accountlessId, accountlessDisplayName, emoji),
                for (final entry in _newPeople.entries)
                  _accountlessRow(
                    entry.key,
                    entry.value['name']! as String,
                    entry.value['emoji'] as String?,
                  ),
              ],
            )['constellationField']
            as Map<String, Object?>;
    for (final peer in (field['peers']! as List).cast<Map<String, Object?>>()) {
      final id = peer['id']! as String;
      peer.addAll({
        ..._photoFields(id),
        'image': {
          '__typename': 'v2_image',
          'id': _publicImageId,
          'author_id': id,
          'created_at': avatarFixtureTime.toIso8601String(),
          'hash': '',
          'width': 4,
          'height': 8,
        },
      });
    }
    final projection = field['anchorProjection']! as Map<String, Object?>;
    projection['anchors'] = [
      for (final entry in _newPeople.entries)
        {
          '__typename': 'v2_ConstellationAnchor',
          'targetKind': 'PHANTOM',
          'targetId': entry.key,
          'revision': '1',
          'placedAt': avatarFixtureTime.toIso8601String(),
          ...(entry.value['position']! as Map<String, Object?>),
        },
    ];
    // Like GraphQL, only emit avatar fields that this request selected. Sending
    // unsolicited fields could hide an incomplete production query.
    final fragments = {
      for (final fragment
          in document.definitions.whereType<FragmentDefinitionNode>())
        fragment.name.value: fragment,
    };
    final selectedGroups = _fields(root.selectionSet, fragments).toList();
    final flags = <String, bool>{};
    for (final group in ['peers', 'phantoms']) {
      final selectedFields = {
        for (final node in selectedGroups.where(
          (node) => node.name.value == group,
        ))
          for (final field in _fields(node.selectionSet, fragments))
            field.name.value: field.alias?.value ?? field.name.value,
      };
      for (final row in (field[group]! as List).cast<Map<String, Object?>>()) {
        for (final key in ['hasPrivateAvatar', 'privateAvatarObjectKey']) {
          final value = row.remove(key);
          if (selectedFields[key] case final responseKey?) {
            row[responseKey] = value;
            if (key == 'hasPrivateAvatar') {
              flags[row['id']! as String] = value! as bool;
            }
          }
        }
      }
    }
    returnedAvatarFlags.add(flags);
    return field;
  }

  Map<String, Object?> _accountlessRow(String id, String name, String? emoji) =>
      constellationPhantomWire(
        id,
        name,
        now: avatarFixtureTime,
        inviteDaysAgo: _invited.contains(id) ? 0 : null,
      )..addAll({'emoji': emoji, ..._photoFields(id)});

  Map<String, Object?> _photoFields(String id) => {
    'hasPrivateAvatar': _privatePhotos.containsKey(id),
    // Support the existing objectKey GET contract as well as a subject GET.
    'privateAvatarObjectKey': _privatePhotos.containsKey(id)
        ? _objectKey(id)
        : null,
  };
}

Iterable<FieldNode> _fields(
  SelectionSetNode? selection,
  Map<String, FragmentDefinitionNode> fragments,
) sync* {
  for (final node in selection?.selections ?? const <SelectionNode>[]) {
    switch (node) {
      case FieldNode():
        yield node;
      case InlineFragmentNode():
        yield* _fields(node.selectionSet, fragments);
      case FragmentSpreadNode():
        yield* _fields(fragments[node.name.value]?.selectionSet, fragments);
    }
  }
}

Uint8List _photoJpeg(int red) {
  final photo = img.Image(width: 8, height: 4)
    ..clear(img.ColorRgb8(red, 120, 185));
  return img.encodeJpg(photo);
}

Map<String, Object?> _decode(String json) =>
    jsonDecode(json) as Map<String, Object?>;

http.StreamedResponse _json(Map<String, Object?> body) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))),
  200,
  headers: {'content-type': 'application/json'},
);

class _JpegPicker extends ImagePickerPlatform {
  _JpegPicker(this.bytes);

  final Uint8List bytes;
  int picks = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    expect(source, ImageSource.gallery);
    picks++;
    return XFile.fromData(bytes, name: 'portrait.jpg', mimeType: 'image/jpeg');
  }
}

// Image.network uses dart:io independently of the HTTP client used for Ferry.
class _ImageClient extends Fake implements HttpClient {
  _ImageClient(this.wire);

  final PrivateAvatarWire wire;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _ImageRequest(wire.imageAt(url));
}

class _ImageRequest extends Fake implements HttpClientRequest {
  _ImageRequest(this.bytes);

  final List<int>? bytes;

  @override
  final HttpHeaders headers = _ImageHeaders();

  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
}

class _ImageHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _ImageResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _ImageResponse(List<int>? bytes)
    : statusCode = bytes == null ? 404 : 200,
      contentLength = bytes?.length ?? 0,
      super(Stream.value(bytes ?? const []));

  @override
  final int statusCode;

  @override
  final int contentLength;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
