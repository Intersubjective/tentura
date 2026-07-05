import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:readmore/readmore.dart';

import 'package:tentura/domain/port/platform_repository_port.dart';

final RegExp _urlPattern = RegExp(r'https?://\S+', caseSensitive: false);

const _trailingPunctuation = '.,;:!?\'"';

/// Annotation set that turns plain-text `http(s)://` URLs into tappable,
/// underlined links (color/tap only -- no widget/state of its own). Plugs
/// into any `ReadMoreText`/`ShowMoreText.annotations` or
/// `buildRoomMessageAnnotatedBodySpan(annotations:)` call site.
List<Annotation> buildUrlAnnotations({
  required Color linkColor,
  Future<void> Function(Uri uri)? onTapLink,
}) {
  final tapLink =
      onTapLink ??
      (uri) => GetIt.I<PlatformRepositoryPort>().launchUserLink(uri);
  return [
    Annotation(
      regExp: _urlPattern,
      spanBuilder: ({required text, textStyle}) =>
          _buildUrlSpan(text, textStyle, linkColor, tapLink),
    ),
  ];
}

/// Character ranges of the linkable (post trailing-punctuation-trim,
/// scheme/host-validated) portion of each URL match in [text]. Used to
/// detect "this tap landed on a link" outside of the annotation/span-builder
/// pipeline (see chat bubble gesture fallback) -- shares [_extractValidUrl]
/// with [_buildUrlSpan] so the two never disagree on what counts as a link.
List<TextRange> findUrlRanges(String text) {
  final ranges = <TextRange>[];
  for (final match in _urlPattern.allMatches(text)) {
    final split = _extractValidUrl(match.group(0)!);
    if (split == null) continue;
    ranges.add(
      TextRange(start: match.start, end: match.start + split.$1.length),
    );
  }
  return ranges;
}

/// Strips trailing punctuation and validates scheme/host; returns null if
/// the remaining token isn't a launchable http(s) link.
(String url, String trailing)? _extractValidUrl(String matched) {
  final (url, trailing) = _splitTrailingPunctuation(matched);
  final uri = Uri.tryParse(url);
  final isValid =
      uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
  return isValid ? (url, trailing) : null;
}

TextSpan _buildUrlSpan(
  String matched,
  TextStyle? textStyle,
  Color linkColor,
  Future<void> Function(Uri uri) onTapLink,
) {
  final split = _extractValidUrl(matched);
  if (split == null) {
    return TextSpan(text: matched, style: textStyle);
  }
  final (url, trailing) = split;
  final uri = Uri.parse(url);

  final linkSpan = TextSpan(
    text: url,
    style: textStyle?.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    ),
    mouseCursor: SystemMouseCursors.click,
    // Rebuilt on every span rebuild; there's no owning State to dispose it
    // in, matching every other recognizer-in-inline-span usage in this repo.
    recognizer: TapGestureRecognizer()..onTap = () => unawaited(onTapLink(uri)),
  );

  if (trailing.isEmpty) return linkSpan;

  return TextSpan(
    style: textStyle,
    children: [
      linkSpan,
      TextSpan(text: trailing),
    ],
  );
}

/// Splits a trailing run of sentence/clause punctuation off a matched URL
/// token: unconditionally for `. , ; : ! ? ' "`, and for closing
/// `) ] }` only when unbalanced within the token itself (so
/// `Foo_(bar)` keeps its `)` but `(see https://x.com)` does not).
(String, String) _splitTrailingPunctuation(String token) {
  var end = token.length;
  while (end > 0) {
    final char = token[end - 1];
    if (_trailingPunctuation.contains(char)) {
      end--;
      continue;
    }
    final closerToOpener = {')': '(', ']': '[', '}': '{'};
    final opener = closerToOpener[char];
    if (opener != null &&
        _countChar(token, opener, end) < _countChar(token, char, end)) {
      end--;
      continue;
    }
    break;
  }
  return (token.substring(0, end), token.substring(end));
}

int _countChar(String s, String char, int end) {
  var count = 0;
  for (var i = 0; i < end; i++) {
    if (s[i] == char) count++;
  }
  return count;
}
