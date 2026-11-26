enum PlaceholderForwardStatus { pending, lapsed }

typedef PlaceholderForward = ({
  String senderId,
  String displayName,
  PlaceholderForwardStatus status,
});
