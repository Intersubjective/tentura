/// Server-side semantic priority for batching and copy.
enum NotificationPriority {
  urgent,
  high,
  normal,
  low,
}

extension NotificationPriorityBand on NotificationPriority {
  /// Two-band batching key: urgent/high vs normal/low.
  String get batchBand => switch (this) {
        NotificationPriority.urgent || NotificationPriority.high => 'high',
        NotificationPriority.normal || NotificationPriority.low => 'normal',
      };

  bool get isHighBand => batchBand == 'high';
}
