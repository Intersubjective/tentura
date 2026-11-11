import 'uploaded_room_attachment.dart';

/// A photo or file saved on a Post draft; publish moves it onto the root
/// message without uploading it again.
typedef PostDraftAttachment = ({String id, UploadedRoomAttachment upload});
