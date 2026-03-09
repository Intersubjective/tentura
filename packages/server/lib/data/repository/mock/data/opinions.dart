import 'package:tentura_server/domain/entity/opinion_entity.dart';

import 'users.dart';

final kOpinionOfThorinForDain = OpinionEntity(
  id: 'O286f94380611',
  author: kUserThorin,
  content: 'My old friend!',
  createdAt: DateTime.now(),
  user: kUserDain,
  score: 1,
);

final kOpinionsById = <String, OpinionEntity>{
  kOpinionOfThorinForDain.id: kOpinionOfThorinForDain,
};
