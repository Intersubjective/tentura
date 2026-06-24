/// Delivery channel a user can opt in/out of per category.
///
/// The in-app Notification Center is intentionally absent here: it is the
/// durable ground truth and is always written, regardless of preferences.
enum NotificationChannel {
  push,
  email,
}
