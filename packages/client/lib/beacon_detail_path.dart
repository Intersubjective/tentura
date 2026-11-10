import 'package:tentura/consts.dart';

/// Product-vocab detail URL prefix (#1082).
String beaconDetailPathPrefix({required bool isPost}) =>
    isPost ? kPathPostView : kPathBeaconView;

bool beaconDetailPathIsPost(String path) =>
    path == kPathPostView || path.startsWith('$kPathPostView/');

bool beaconDetailPathIsRequest(String path) =>
    path == kPathBeaconView || path.startsWith('$kPathBeaconView/');

/// Canonical in-app / deep-link path for a Post or Request detail screen.
String beaconDetailPathFor(
  String id, {
  required bool isPost,
  Map<String, String> queryParameters = const {},
}) {
  final prefix = beaconDetailPathPrefix(isPost: isPost);
  final base = '$prefix/$id';
  if (queryParameters.isEmpty) return base;
  return '$base?${Uri(queryParameters: queryParameters).query}';
}
