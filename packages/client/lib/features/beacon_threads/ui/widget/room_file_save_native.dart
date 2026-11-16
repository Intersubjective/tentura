import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Hands [bytes] to the platform share/open sheet under [name]. A sheet the
/// user dismisses is not an error.
Future<void> saveRoomFile(Uint8List bytes, String name, String mime) =>
    SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: mime)],
        fileNameOverrides: [name],
      ),
    );
