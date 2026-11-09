// Limits and `person_tag_member.source` codes for an owner's person tags.

const kPersonTagMaxNameLength = 32;
const kPersonTagMaxGlyphUnits = 8;
const kPersonTagColors = 8;
const kPersonTagMaxOpsPerCall = 400;

/// `person_tag_member.source`: how a person came to be in a tag.
const kPersonTagSourceManual = 0;
const kPersonTagSourceFromAutoTag = 2;
const kPersonTagSourceFromRequest = 3;

/// Copied from the person's inviter when they were first seen on the Field.
const kPersonTagSourceInherited = 4;
const kPersonTagMaxSource = kPersonTagSourceInherited;
