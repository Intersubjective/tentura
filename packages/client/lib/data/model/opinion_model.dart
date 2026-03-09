import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/domain/entity/opinion.dart';

import '../gql/_g/opinion_model.data.gql.dart';

extension type const OpinionModel(GOpinionModel i) implements GOpinionModel {
  Opinion get asEntity => Opinion(
    id: id,
    amount: i.amount,
    content: i.content,
    objectId: i.object,
    createdAt: i.created_at,
    author: (i.author! as UserModel).toEntity(),
    score: double.tryParse(i.scores?.firstOrNull?.dst_score?.value ?? '') ?? 0,
  );
}
