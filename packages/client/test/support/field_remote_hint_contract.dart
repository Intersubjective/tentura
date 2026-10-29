// Pure wire contract shared with the server PG test. Keep this file free of
// package imports so each package can compile and generate code independently.
const remoteHintViewerId = 'Uaaaaaaaaaaaa';
const remoteHintContactId = 'Ubbbbbbbbbbbb';

Map<String, Object> remoteRequestFrame(String requestId) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': 'constellation_item',
    'id': requestId,
    'event': 'insert',
    'actor_user_id': remoteHintContactId,
  },
};

Map<String, Object> remoteUntrustFrame(String operation) => {
  'type': 'subscription',
  'path': 'entity_changes',
  'payload': {
    'entity': 'relationship',
    'id': remoteHintViewerId,
    'event': operation,
    'actor_user_id': remoteHintContactId,
  },
};
