import 'dart:convert';

import 'package:web/web.dart' as web;

const _storageKey = 'tentura_post_create_composer';

class PostCreateComposerDraftSnapshot {
  const PostCreateComposerDraftSnapshot({
    required this.body,
    this.draftId,
  });

  final String? draftId;
  final String body;
}

PostCreateComposerDraftSnapshot? readPostCreateComposerDraft() {
  try {
    final raw = web.window.sessionStorage.getItem(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    final map = jsonDecode(raw);
    if (map is! Map) return null;
    final body = map['body']?.toString() ?? '';
    if (body.trim().isEmpty) return null;
    final draftId = map['draftId']?.toString();
    return PostCreateComposerDraftSnapshot(
      draftId: draftId == null || draftId.isEmpty ? null : draftId,
      body: body,
    );
  } catch (_) {
    return null;
  }
}

void writePostCreateComposerDraft({
  required String body,
  String? draftId,
}) {
  final trimmed = body.trim();
  if (trimmed.isEmpty && (draftId == null || draftId.isEmpty)) {
    clearPostCreateComposerDraft();
    return;
  }
  final payload = <String, Object?>{
    'body': body,
    if (draftId != null && draftId.isNotEmpty) 'draftId': draftId,
  };
  web.window.sessionStorage.setItem(_storageKey, jsonEncode(payload));
}

void clearPostCreateComposerDraft() {
  web.window.sessionStorage.removeItem(_storageKey);
}

void resetPostCreateComposerDraftStoreForTest() {}
