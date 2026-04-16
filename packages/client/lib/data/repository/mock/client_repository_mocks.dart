// Repository test doubles for injectable [Environment.test].
// ignore_for_file: dangling_library_doc_comments, unnecessary_import

import 'package:injectable/injectable.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/app_update_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';

import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/auth/domain/port/auth_remote_repository_port.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_view/data/repository/beacon_view_repository.dart';
import 'package:tentura/features/beacon_view/data/repository/coordination_repository.dart';

import 'package:tentura/features/chat/domain/port/chat_local_repository_port.dart';
import 'package:tentura/features/chat/domain/port/chat_remote_repository_port.dart';

import 'package:tentura/features/comment/data/repository/comment_repository.dart';
import 'package:tentura/features/complaint/data/repository/complaint_repository.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';

import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/favorites/data/repository/favorites_remote_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/geo/data/repository/geo_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_repository.dart';

import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';

import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';

import 'package:tentura/features/notification/domain/port/fcm_local_repository_port.dart';
import 'package:tentura/features/notification/domain/port/fcm_remote_repository_port.dart';

import 'package:tentura/features/opinion/data/repository/opinion_repository.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/data/repository/mutual_friends_repository.dart';

import 'package:tentura/features/rating/data/repository/rating_repository.dart';
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';

@Injectable(as: ComplaintRepository, env: [Environment.test], order: 1)
class ComplaintRepositoryMock extends Mock implements ComplaintRepository {}

@Injectable(as: InboxRepository, env: [Environment.test], order: 1)
class InboxRepositoryMock extends Mock implements InboxRepository {}

@Injectable(as: GraphRepository, env: [Environment.test], order: 1)
class GraphRepositoryMock extends Mock implements GraphRepository {}

@Injectable(as: ChatLocalRepositoryPort, env: [Environment.test], order: 1)
class ChatLocalRepositoryMock extends Mock implements ChatLocalRepositoryPort {}

@Injectable(as: ChatRemoteRepositoryPort, env: [Environment.test], order: 1)
class ChatRemoteRepositoryMock extends Mock implements ChatRemoteRepositoryPort {}

@Injectable(as: InvitationRepository, env: [Environment.test], order: 1)
class InvitationRepositoryMock extends Mock implements InvitationRepository {}

@Injectable(as: EvaluationRepository, env: [Environment.test], order: 1)
class EvaluationRepositoryMock extends Mock implements EvaluationRepository {}

@Injectable(as: CoordinationRepository, env: [Environment.test], order: 1)
class CoordinationRepositoryMock extends Mock implements CoordinationRepository {}

@Injectable(as: AuthLocalRepositoryPort, env: [Environment.test], order: 1)
class AuthLocalRepositoryMock extends Mock implements AuthLocalRepositoryPort {}

@Injectable(as: FavoritesRemoteRepository, env: [Environment.test], order: 1)
class FavoritesRemoteRepositoryMock extends Mock
    implements FavoritesRemoteRepository {}

@Injectable(as: ForwardRepository, env: [Environment.test], order: 1)
class ForwardRepositoryMock extends Mock implements ForwardRepository {}

@Injectable(as: AuthRemoteRepositoryPort, env: [Environment.test], order: 1)
class AuthRemoteRepositoryMock extends Mock implements AuthRemoteRepositoryPort {}

@Injectable(as: CommentRepository, env: [Environment.test], order: 1)
class CommentRepositoryMock extends Mock implements CommentRepository {}

@Injectable(as: FriendsRemoteRepository, env: [Environment.test], order: 1)
class FriendsRemoteRepositoryMock extends Mock implements FriendsRemoteRepository {}

@Injectable(as: RatingRepository, env: [Environment.test], order: 1)
class RatingRepositoryMock extends Mock implements RatingRepository {}

@Injectable(as: FcmLocalRepositoryPort, env: [Environment.test], order: 1)
class FcmLocalRepositoryMock extends Mock implements FcmLocalRepositoryPort {}

@Injectable(as: LikeRemoteRepository, env: [Environment.test], order: 1)
class LikeRemoteRepositoryMock extends Mock implements LikeRemoteRepository {}

@Injectable(as: ImageRepository, env: [Environment.test], order: 1)
class ImageRepositoryMock extends Mock implements ImageRepository {}

@Injectable(as: AppUpdateRepository, env: [Environment.test], order: 1)
class AppUpdateRepositoryMock extends Mock implements AppUpdateRepository {}

@Injectable(as: GeoRepository, env: [Environment.test], order: 1)
class GeoRepositoryMock extends Mock implements GeoRepository {}

@Injectable(as: OpinionRepository, env: [Environment.test], order: 1)
class OpinionRepositoryMock extends Mock implements OpinionRepository {}

@Injectable(as: MyWorkRepository, env: [Environment.test], order: 1)
class MyWorkRepositoryMock extends Mock implements MyWorkRepository {}

@Injectable(as: ProfileRepositoryPort, env: [Environment.test], order: 1)
class ProfileRepositoryMock extends Mock implements ProfileRepositoryPort {}

@Injectable(as: BeaconViewRepository, env: [Environment.test], order: 1)
class BeaconViewRepositoryMock extends Mock implements BeaconViewRepository {}

@Injectable(as: BeaconRepository, env: [Environment.test], order: 1)
class BeaconRepositoryMock extends Mock implements BeaconRepository {}

@Injectable(as: PollingRepository, env: [Environment.test], order: 1)
class PollingRepositoryMock extends Mock implements PollingRepository {}

@Injectable(as: ContextRepository, env: [Environment.test], order: 1)
class ContextRepositoryMock extends Mock implements ContextRepository {}

@Injectable(as: PlatformRepositoryPort, env: [Environment.test], order: 1)
class PlatformRepositoryMock extends Mock implements PlatformRepositoryPort {}

@Injectable(as: SettingsRepositoryPort, env: [Environment.test], order: 1)
class SettingsRepositoryMock extends Mock implements SettingsRepositoryPort {}

@Injectable(as: MutualFriendsRepository, env: [Environment.test], order: 1)
class MutualFriendsRepositoryMock extends Mock implements MutualFriendsRepository {}

@Injectable(as: FcmRemoteRepositoryPort, env: [Environment.test], order: 1)
class FcmRemoteRepositoryMock extends Mock implements FcmRemoteRepositoryPort {}
