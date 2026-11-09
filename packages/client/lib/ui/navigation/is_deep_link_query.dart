/// Whether a browse detail route's `is_deep_link` query means a cold stack.
bool isDeepLinkQueryTruthy(String? value) {
  if (value == null || value.isEmpty) return false;
  final normalized = value.toLowerCase();
  return normalized != 'false' && normalized != '0';
}
