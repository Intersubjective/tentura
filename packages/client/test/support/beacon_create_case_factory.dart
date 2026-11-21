import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';

import '../features/beacon_create/fake_beacon_ports.dart';

BeaconCreateCase buildBeaconCreateCase({
  BeaconWritePort? beacons,
  BeaconImagePort? images,
}) => BeaconCreateCase(
  beacons ?? FakeBeaconWritePort(),
  images ?? FakeBeaconImagePort(),
);
