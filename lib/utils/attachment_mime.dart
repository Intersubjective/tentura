// PNG and WebP retain the client's specific types. GIF, HEIC and HEIF retain
// the server's historical JPEG fallback when only the extension is available.
const _attachmentMimeTypes = {
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/jpeg',
  'heic': 'image/jpeg',
  'heif': 'image/jpeg',
};

/// MIME fallback for a file extension without its leading dot.
String attachmentMimeFromExtension(String extension) =>
    _attachmentMimeTypes[extension.toLowerCase()] ?? 'application/octet-stream';
