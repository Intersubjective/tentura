import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/image_entity.dart';

import 'users.dart';

const kB20f3d51e498f = 'B20f3d51e498f';
const kBc1cb783b0159 = 'Bc1cb783b0159';

/// Mock data for tests and dev mode
final kBeaconById = <String, BeaconEntity>{
  // Beacon with picture and comments
  kBc1cb783b0159: BeaconEntity(
    id: kBc1cb783b0159,
    title: 'The Quest for Glory Awaits!',
    description: '''
Durin's Kin, our noble company seeks valiant souls to join us in our grand endeavor to reclaim the Lonely Mountain from the vile Smaug. If you possess the heart of a true dwarf and the mettle to face fire and darkness, we welcome your blade and your courage. Our quest is not for the faint-hearted, but for those who yearn for honor and glory.

Requirements:
 – Expertise with axe or sword
 – An appreciation for fine gold and gemcraft
 – A robust constitution to withstand dragon fire and goblin ambushes

If you are bold enough to stand among dwarves of valor, reply to this call or send a raven. Please, only those who are committed to the cause and not easily deterred by peril. And kindly, leave behind those who speak only of their uncles’ exaggerated tales of elvish grandeur. Our journey is fraught with danger, but for those who stand with us, there is a treasure beyond dreams and tales of heroism.''',
    context: 'QuestForGlory',
    createdAt: DateTime(2024, 10, 03),
    updatedAt: DateTime(2024, 10, 03),
    startAt: DateTime(2024, 10, 03),
    endAt: DateTime(2025, 10, 03),
    coordinates: const Coordinates(lat: 10.20, long: -20.50),
    image: ImageEntity(
      id: 'e2e9107c-6b73-49f2-a62f-8c010d4434c6',
      authorId: kUserThorin.id,
      blurHash:
          'q9DTa-Dk={_L-o?tHtRQRQM{r?4p%foxyB%LV@RjNHj[s.M|s:WBIVs:x@x[WDxtafV[%LofWERjV[RkM|V@RRWBVtayW;j@tjWC',
      height: 337,
      width: 600,
    ),
    // TBD: add image parameters
    author: kUserThorin,
  ),

  // Beacon without picture and comments
  kB20f3d51e498f: BeaconEntity(
    id: kB20f3d51e498f,
    title: 'Protect Our Forests',
    description: '''
Dear citizens of Middle-earth, it has come to my attention that recent events have left our beloved forests in peril. The reckless antics of certain individuals, including those who claim to be guardians of our realm, have resulted in devastating fires that threaten our natural beauty and the cultural traditions intertwined with it.
As a concerned neighbor and advocate for the preservation of our environment, I urge each of you to join me in raising awareness and funds for the restoration of these precious lands. Together, we can combat the damage done and promote sustainable practices that honor both nature and our shared heritage.
Let us not forget: true guardianship means safeguarding our world for future generations. Remember, not all heroes wear capes—some hold the power of nature in their hands.''',
    createdAt: DateTime(2024, 10, 05, 09, 06, 32),
    updatedAt: DateTime(2024, 10, 05, 09, 06, 32),
    author: kUserByPublicKey[kAnonymousKey]!,
  ),
};
