/// An id-anchored mention range while it is being composed.
///
/// This UI-model value deliberately lives outside the text-field widget: the
/// composer owns its tracking, while the cubit consumes the resulting command.
typedef CommittedMention = ({String userId, int start, int end});
