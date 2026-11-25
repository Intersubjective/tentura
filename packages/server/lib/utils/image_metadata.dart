import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:image/image.dart';

({String hash, int height, int width}) describeImage(
  Image image, [
  int maxComponents = 8,
  int minComponents = 6,
]) {
  final components = image.height == image.width
      ? (x: maxComponents, y: maxComponents)
      : image.height > image.width
      ? (x: minComponents, y: maxComponents)
      : (x: maxComponents, y: minComponents);
  return (
    hash: BlurHash.encode(
      image,
      numCompX: components.x,
      numCompY: components.y,
    ).hash,
    height: image.height,
    width: image.width,
  );
}
