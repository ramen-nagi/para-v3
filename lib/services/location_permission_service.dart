import 'package:permission_handler/permission_handler.dart';

enum LocationPermissionState { granted, denied, permanentlyDenied }

class LocationPermissionService {
  const LocationPermissionService();

  Future<LocationPermissionState> checkPermission() async {
    return _toState(await Permission.locationWhenInUse.status);
  }

  Future<LocationPermissionState> requestPermission() async {
    final currentStatus = await Permission.locationWhenInUse.status;
    if (currentStatus.isPermanentlyDenied) {
      return LocationPermissionState.permanentlyDenied;
    }
    return _toState(await Permission.locationWhenInUse.request());
  }

  Future<bool> openSettings() => openAppSettings();

  LocationPermissionState _toState(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return LocationPermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return LocationPermissionState.permanentlyDenied;
    }
    return LocationPermissionState.denied;
  }
}
