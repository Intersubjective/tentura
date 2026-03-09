import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/user_model.data.gql.dart';
import 'image_model.dart';

extension type const UserModel(GUserModel i) implements GUserModel {
  Profile toEntity({ImageModel? image}) => Profile(
    id: i.id,
    title: i.title,
    description: i.description,
    myVote: i.my_vote ?? 0,
    image: (i.image as ImageModel?)?.asEntity ?? image?.asEntity,
    score: double.tryParse(i.scores?.first.dst_score?.value ?? '') ?? 0,
    rScore: double.tryParse(i.scores?.first.src_score?.value ?? '') ?? 0,
  );
}
