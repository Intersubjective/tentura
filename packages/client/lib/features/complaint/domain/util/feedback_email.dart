final RegExp _feedbackEmailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isValidFeedbackEmail(String value) {
  final trimmed = value.trim();
  return trimmed.isNotEmpty && _feedbackEmailPattern.hasMatch(trimmed);
}
