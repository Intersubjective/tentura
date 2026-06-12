// Coordination item source (origin); persisted on `coordination_item.source`.
const int coordinationItemSourceDefault = 0;

// Coordination item kind values.
const int coordinationItemKindPlan = 1;
const int coordinationItemKindAsk = 2;
const int coordinationItemKindBlocker = 3;
const int coordinationItemKindResolution = 4;
const int coordinationItemKindPromise = 5;

// Coordination item status values.
const int coordinationItemStatusOpen = 0;
const int coordinationItemStatusAccepted = 1;
const int coordinationItemStatusResolved = 2;
const int coordinationItemStatusCancelled = 3;
const int coordinationItemStatusSuperseded = 4;

const int kCoordinationItemDefaultStaleDays = 3;
const int kCoordinationItemMaxStaleDays = 90;
const int kCoordinationItemRemindCooldownHours = 24;

// Coordination item event kind values (used in room_messages.linked_event_kind).
const int coordinationEventKindCreated = 1;
const int coordinationEventKindAccepted = 2;
const int coordinationEventKindResolved = 3;
const int coordinationEventKindCancelled = 4;
const int coordinationEventKindUpdated = 5;
const int coordinationEventKindSuperseded = 6;
