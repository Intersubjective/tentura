import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';

/// Optimistic reaction toggle matching server semantics: one row per
/// (message, user, emoji); [RoomMessage.myReaction] is comma-sorted distinct
/// emojis for the viewer.
RoomMessage toggleRoomMessageReactionLocally(
  RoomMessage message,
  String emoji,
  Profile myProfile,
) {
  final raw = message.myReaction;
  final viewerEmojis = <String>[];
  if (raw != null && raw.isNotEmpty) {
    viewerEmojis.addAll(
      raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
    );
  }
  final had = viewerEmojis.contains(emoji);

  final nextViewer = <String>[...viewerEmojis];
  if (had) {
    nextViewer.remove(emoji);
  } else {
    nextViewer.add(emoji);
  }
  final uniqueViewer = nextViewer.toSet().toList()..sort();

  final newCounts = Map<String, int>.from(message.reactionCounts);
  if (had) {
    final prev = newCounts[emoji] ?? 0;
    final next = prev > 0 ? prev - 1 : 0;
    if (next <= 0) {
      newCounts.remove(emoji);
    } else {
      newCounts[emoji] = next;
    }
  } else {
    newCounts[emoji] = (newCounts[emoji] ?? 0) + 1;
  }

  final nextReactors = <String, List<Profile>>{};
  for (final e in message.reactors.entries) {
    nextReactors[e.key] = List<Profile>.from(e.value);
  }
  final reactorList = nextReactors.putIfAbsent(emoji, () => <Profile>[])
    ..removeWhere((p) => p.id == myProfile.id);
  if (had) {
    if (reactorList.isEmpty) {
      nextReactors.remove(emoji);
    }
  } else {
    reactorList.insert(0, myProfile);
  }

  return message.copyWith(
    myReaction: uniqueViewer.isEmpty ? null : uniqueViewer.join(','),
    reactionCounts: newCounts,
    reactors: nextReactors,
  );
}
