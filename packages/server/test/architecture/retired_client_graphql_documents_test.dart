import 'dart:io';

import 'package:test/test.dart';

void main() {
  final gqlDir = Directory('../client/lib/features/coordination_item/data/gql');

  const retiredBasenames = {
    'coordination_item_mark_blocker.graphql',
    'coordination_item_mark_ask.graphql',
    'coordination_item_resolve_blocker.graphql',
    'coordination_item_cancel_blocker.graphql',
    'coordination_item_create_promise.graphql',
    'coordination_item_create_draft_promise.graphql',
    'coordination_item_publish_promise.graphql',
    'coordination_item_update_draft_promise.graphql',
    'coordination_item_delete_draft_promise.graphql',
    'coordination_item_accept_promise.graphql',
    'coordination_item_resolve_promise.graphql',
    'coordination_item_cancel_promise.graphql',
    'coordination_item_redirect_promise.graphql',
    'coordination_item_create_draft_ask.graphql',
    'coordination_item_publish_ask.graphql',
    'coordination_item_update_draft_ask.graphql',
    'coordination_item_delete_draft_ask.graphql',
    'coordination_item_create_draft_blocker.graphql',
    'coordination_item_publish_blocker.graphql',
    'coordination_item_update_draft_blocker.graphql',
    'coordination_item_delete_draft_blocker.graphql',
    'coordination_item_accept_ask.graphql',
    'coordination_item_resolve_ask.graphql',
    'coordination_item_cancel_ask.graphql',
    'coordination_item_redirect_ask.graphql',
  };

  test('retired coordination-item client GraphQL documents are removed', () {
    expect(gqlDir.existsSync(), isTrue);
    final present = gqlDir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.graphql'))
        .toSet();
    expect(present.intersection(retiredBasenames), isEmpty);
    expect(retiredBasenames.difference(present).length, retiredBasenames.length);
  });
}
