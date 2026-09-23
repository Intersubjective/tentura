final class RoomReadWatermarkRecord {
  const RoomReadWatermarkRecord({
    required this.userId,
    required this.lastSeenAt,
    required this.userTitle,
    required this.userHasPicture,
    required this.userImageId,
    required this.userBlurHash,
    required this.userPicHeight,
    required this.userPicWidth,
  });

  final String userId;
  final DateTime lastSeenAt;
  final String userTitle;
  final bool userHasPicture;
  final String userImageId;
  final String userBlurHash;
  final int userPicHeight;
  final int userPicWidth;
}
