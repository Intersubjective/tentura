import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart'
    show mintGraphLayoutTicket;
import 'package:force_directed_graphview/src/scene/graph_presentation_token.dart'
    show mintGraphPresentationToken;

void main() {
  test('presentation tokens distinguish controller owners', () {
    final a = mintGraphPresentationToken(owner: Object(), sequence: 1);
    final b = mintGraphPresentationToken(owner: Object(), sequence: 1);
    expect(a, isNot(equals(b)));
  });

  test('public types accept controller-minted tickets only via in-package mint',
      () {
    final ticket = mintGraphLayoutTicket(
      owner: Object(),
      topologyRevision: 2,
      generation: 3,
    );
    final layout = SceneLayout(
      ticket: ticket,
      revision: 1,
      positions: const {},
    );
    expect(layout.ticket.topologyRevision, 2);
    expect(layout.ticket.generation, 3);
  });
}
