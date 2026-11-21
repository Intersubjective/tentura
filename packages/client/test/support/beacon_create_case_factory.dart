import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/port/op_id_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';

import '../features/beacon_create/fake_beacon_ports.dart';

BeaconCreateCase buildBeaconCreateCase({
  BeaconWritePort? beacons,
  BeaconImagePort? images,
  OpIdPort? opIds,
}) => BeaconCreateCase(
  beacons ?? FakeBeaconWritePort(),
  images ?? FakeBeaconImagePort(),
  opIds ?? OpIdService(),
);
