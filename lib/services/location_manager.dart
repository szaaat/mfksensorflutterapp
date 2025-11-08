import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'dart:developer' as developer;

class LocationManager {
  Position? _latestLocation;
  bool _isGPSActive = false;

  final StreamController<Position> _locationController = StreamController<Position>.broadcast();
  final StreamController<LocationServiceStatus> _statusController = StreamController<LocationServiceStatus>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  Stream<Position> get onLocationUpdated => _locationController.stream;
  Stream<LocationServiceStatus> get onStatusChanged => _statusController.stream;
  Stream<String> get onError => _errorController.stream;

  Position? get lastKnownLocation => _latestLocation;

  LocationManager() {
    _initialize();
  }

  Future<void> _initialize() async {
    await _requestPermission();
    await startUpdatingLocation();
  }

  Future<void> _requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      developer.log('LocationManager: Permission requested: $permission');
    }

    if (permission == LocationPermission.deniedForever) {
      _errorController.add('Location permissions are permanently denied');
      developer.log('LocationManager: Location permissions permanently denied');
      return;
    }

    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      developer.log('LocationManager: Location permission granted: $permission');
    } else {
      developer.log('LocationManager: Location permission not granted: $permission');
    }
  }

  Future<void> startUpdatingLocation() async {
    developer.log('LocationManager: Starting location updates');

    try {
      _isGPSActive = true;
      _statusController.add(LocationServiceStatus.active);

      // Először próbáljunk meg egy azonnali pozíciót kapni
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        );
        _updateLocation(position);
        developer.log('LocationManager: Initial position acquired');
      } catch (e) {
        developer.log('LocationManager: Error getting initial position: $e');
      }

      // Folyamatos frissítések
      Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 1, // 1 méter változásra frissít
        ),
      ).listen(
        _updateLocation,
        onError: (error) {
          developer.log('LocationManager: Location stream error: $error');
          _errorController.add(error.toString());
          _isGPSActive = false;
          _statusController.add(LocationServiceStatus.error);
        },
        cancelOnError: false,
      );

      developer.log('LocationManager: Location updates started successfully');

    } catch (e) {
      developer.log('LocationManager: Error starting location updates: $e');
      _errorController.add(e.toString());
      _isGPSActive = false;
      _statusController.add(LocationServiceStatus.inactive);
    }
  }

  void _updateLocation(Position position) {
    _latestLocation = position;
    _isGPSActive = true;
    developer.log('LocationManager: New location: ${position.latitude}, ${position.longitude}');
    _locationController.add(position);
    _statusController.add(LocationServiceStatus.active);
  }

  Future<void> stopUpdatingLocation() async {
    developer.log('LocationManager: Stopping location updates');
    _isGPSActive = false;
    _statusController.add(LocationServiceStatus.inactive);
  }

  bool isGPSActive() => _isGPSActive;
  Position? getLastKnownLocation() => _latestLocation;

  void dispose() {
    _locationController.close();
    _statusController.close();
    _errorController.close();
  }
}

enum LocationServiceStatus {
  active,
  inactive,
  error
}
