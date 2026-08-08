import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura_root/domain/enums.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

Profile _profile({
  String id = 'Ualice',
  String displayName = 'Alice',
  double score = 1,
  double rScore = 0,
  int myVote = 0,
  bool subjectExplicitlyTrustsViewer = false,
  bool isMutualFriend = false,
  String description = 'bio',
  UserPresenceStatus? presenceStatus = UserPresenceStatus.online,
}) => Profile(
  id: id,
  displayName: displayName,
  score: score,
  rScore: rScore,
  myVote: myVote,
  subjectExplicitlyTrustsViewer: subjectExplicitlyTrustsViewer,
  isMutualFriend: isMutualFriend,
  description: description,
  presenceStatus: presenceStatus,
);

void main() {
  group('UserNode', () {
    test('myVote change is distinguishable', () {
      final a = UserNode(user: _profile(myVote: 0));
      final b = UserNode(user: _profile(myVote: 1));
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
    });

    test('incoming-trust-only change is distinguishable', () {
      final a = UserNode(user: _profile(subjectExplicitlyTrustsViewer: false));
      final b = UserNode(
        user: _profile(subjectExplicitlyTrustsViewer: true),
      );
      expect(a, isNot(b));
    });

    test('rScore change is distinguishable', () {
      final a = UserNode(user: _profile(rScore: 0));
      final b = UserNode(user: _profile(rScore: 0.5));
      expect(a, isNot(b));
    });

    test('isMutualFriend change is distinguishable', () {
      final a = UserNode(user: _profile(isMutualFriend: false));
      final b = UserNode(user: _profile(isMutualFriend: true));
      expect(a, isNot(b));
    });

    test('isHelpOfferer survives in equality', () {
      final a = UserNode(user: _profile(), isHelpOfferer: false);
      final b = UserNode(user: _profile(), isHelpOfferer: true);
      expect(a, isNot(b));
    });

    test('description and presence do not affect equality', () {
      final a = UserNode(
        user: _profile(
          description: 'one',
          presenceStatus: UserPresenceStatus.online,
        ),
      );
      final b = UserNode(
        user: _profile(
          description: 'two',
          presenceStatus: UserPresenceStatus.offline,
        ),
      );
      expect(a, b);
    });
  });

  group('GenealogyUserNode', () {
    test('relationship fields are compared like UserNode', () {
      final a = GenealogyUserNode(
        nodeKey: 'Galice',
        user: _profile(myVote: 0, subjectExplicitlyTrustsViewer: false),
      );
      final b = GenealogyUserNode(
        nodeKey: 'Galice',
        user: _profile(myVote: 1, subjectExplicitlyTrustsViewer: true),
      );
      expect(a, isNot(b));
    });

    test('nodeKey is part of identity via base id', () {
      final profile = _profile();
      final a = GenealogyUserNode(nodeKey: 'G1', user: profile);
      final b = GenealogyUserNode(nodeKey: 'G2', user: profile);
      expect(a, isNot(b));
    });

    test('rScore change is distinguishable', () {
      final a = GenealogyUserNode(
        nodeKey: 'G1',
        user: _profile(rScore: 0),
      );
      final b = GenealogyUserNode(
        nodeKey: 'G1',
        user: _profile(rScore: 2),
      );
      expect(a, isNot(b));
    });
  });
}
