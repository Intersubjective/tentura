import 'package:tentura_server/domain/entity/image_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

const kAnonymousKey = '0E_W6fNl_e9zk-YtRWlHTNVQnTBkxK2csCtfkdxeCVc';
const kDainKey = '60qBqhlXQzNOvlgK9h1FdxzpZX18EcC2A-6vqr_ABu8';
const kGandalfKey = 'DpywC3XZqDJFLyey0w11Ms1dX2I1RWgEl5Ps-tONuo8';
const kPussyCatKey = '2CmIb3Ho2eb6m8WIog6KiyzCY05sbyX04PiGlH5baDw';
const kThorinKey = 'iqjH7nwdD1CBa-XgaW90yY443ghL8RC0Za-hKv-aeGg';

const kUserThorin = UserEntity(
  id: 'U286f94380611',
  title: 'Thorin Oakenshield',
  description: 'Son of Thrain, son of Thror, King under the Mountain',
  image: ImageEntity(
    id: '5edb9b09-e0af-408e-8c45-4b047abf1237',
    authorId: 'U286f94380611',
    blurHash:
        r'-HB2.D%20$Ip-U%1$koLEgR*s:t6I=WV%1WVNGRk5RNG-TxZI:Rk9]WC-TxZW'
        'VS3oyj[WBoLofj[t6a}RkafkCoyj[oeoej[aeRk',
    height: 512,
    width: 341,
  ),
);

const kUserDain = UserEntity(
  id: 'U8ebde6fbfd3f',
  title: 'Dain Ironfoot',
  description:
      'CEO of Ironfoot Industries and the Lord of the Iron Hills. '
      'Veteran in resource extraction and heavy manufacturing. '
      'When the chips are down, I’m the guy you want in your corner. '
      'Tough decisions? I make them every day. 👊 '
      'Always looking for the next big opportunity in heavy industry '
      'and infrastructure.',
  image: ImageEntity(
    id: '1d2f8fae-28ab-47e6-b9ae-361f35013dab',
    authorId: 'U8ebde6fbfd3f',
    blurHash:
        r'qECY,UodSz~BX8M{xZn$-p%1xt%1s,oc$%WXV@RjM|R*ayoexaofI;NGIpNHR+kCj['
        'R*D*R-NbNGNHkCbHWXIokCkCNGa}ofoeoe',
    height: 425,
    width: 600,
  ),
);

const kUserGandalf = UserEntity(
  id: 'U2becfc64c13b',
  title: 'Gandalf the Gray',
  description:
      'Experienced business angel and startup mentor with a knack '
      'for turning risky ventures into legendary success stories. '
      'Disrupting the market since before it was cool. '
      'Occasionally disappear to let teams find their own path, but always '
      'return at the right moment. DM for networking and strategic advice.',
  image: ImageEntity(
    id: 'd2595507-884d-4cf0-bb10-600d89a9e474',
    authorId: 'U2becfc64c13b',
    blurHash:
        '-#G+adIU%MozWBWB~qj?xuj[WBWV?bj[jsozRjayxut7RjofWBWBWBxtRkWBt7WBjZa'
        'yWBWBt7f6WBWBRkWBofofofRjaeWBfQt7',
    height: 756,
    width: 600,
  ),
);

const kUserAnonymous = UserEntity(
  id: 'U4d9267c70eab',
  title: 'The Anonymous of Dol Guldur',
  description: '''
Let's save the nature and cultural traditions of Middle-earth! 

Activist, publicist, concerned neighbor and representative of one of the largest communities in Middle-earth.''',
);

/// Mock data for tests and dev mode
const kUserByPublicKey = <String, UserEntity>{
  kDainKey: kUserDain,
  kThorinKey: kUserThorin,
  kGandalfKey: kUserGandalf,

  // User without picture
  kAnonymousKey: kUserAnonymous,

  // User for auth test
  kPussyCatKey: UserEntity(
    id: 'U3ea0a229ad85',
    title: 'Pussy Cat',
  ),
};
