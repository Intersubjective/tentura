import 'package:test/test.dart';
import 'package:tentura/features/beacon_view/domain/beacon_surface_mode.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_entry_source.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_surface_resolver.dart';

void main() {
  group('resolveInitialBeaconSurfaceMode', () {
    test('explicit status wins over explicit room when both true', () {
      expect(
        resolveInitialBeaconSurfaceMode(
          entry: BeaconViewEntrySource.deepLink,
          hasRoomAccess: true,
          explicitRoomRequested: true,
          explicitStatusRequested: true,
        ),
        BeaconSurfaceMode.status,
      );
    });

    test('explicit room + access => room', () {
      expect(
        resolveInitialBeaconSurfaceMode(
          entry: BeaconViewEntrySource.inbox,
          hasRoomAccess: true,
          explicitRoomRequested: true,
          explicitStatusRequested: false,
        ),
        BeaconSurfaceMode.room,
      );
    });

    test('explicit room + no access => status', () {
      expect(
        resolveInitialBeaconSurfaceMode(
          entry: BeaconViewEntrySource.inbox,
          hasRoomAccess: false,
          explicitRoomRequested: true,
          explicitStatusRequested: false,
        ),
        BeaconSurfaceMode.status,
      );
    });

    test('myWork implicit => status even with room access', () {
      expect(
        resolveInitialBeaconSurfaceMode(
          entry: BeaconViewEntrySource.myWork,
          hasRoomAccess: true,
          explicitRoomRequested: false,
          explicitStatusRequested: false,
        ),
        BeaconSurfaceMode.status,
      );
    });

    test('myWork implicit + no room access => status', () {
      expect(
        resolveInitialBeaconSurfaceMode(
          entry: BeaconViewEntrySource.myWork,
          hasRoomAccess: false,
          explicitRoomRequested: false,
          explicitStatusRequested: false,
        ),
        BeaconSurfaceMode.status,
      );
    });

    test('inbox implicit => status', () {
      expect(
        resolveInitialBeaconSurfaceMode(
          entry: BeaconViewEntrySource.inbox,
          hasRoomAccess: true,
          explicitRoomRequested: false,
          explicitStatusRequested: false,
        ),
        BeaconSurfaceMode.status,
      );
    });

    test('roomNotification + access => room', () {
      expect(
        resolveInitialBeaconSurfaceMode(
          entry: BeaconViewEntrySource.roomNotification,
          hasRoomAccess: true,
          explicitRoomRequested: false,
          explicitStatusRequested: false,
        ),
        BeaconSurfaceMode.room,
      );
    });
  });

  group('explicitRoomSurfaceRequested', () {
    test('detects surface=room', () {
      expect(
        explicitRoomSurfaceRequested(
          surfaceQuery: 'room',
          navigatedFromLegacyRoomPath: false,
          sharedLinkDestRoom: false,
        ),
        isTrue,
      );
    });
  });

  group('explicitStatusSurfaceRequested', () {
    test('non-null viewTab => status surface', () {
      expect(
        explicitStatusSurfaceRequested(
          surfaceQuery: null,
          viewTab: 'overview',
        ),
        isTrue,
      );
    });
  });
}
