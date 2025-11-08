import 'dart:async';
import 'dart:ui';
import 'dart:developer' as developer;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mfk_sensor/services/ble_manager.dart';
import 'package:mfk_sensor/services/location_manager.dart';
import 'package:mfk_sensor/services/database_manager.dart';
import 'package:mfk_sensor/services/supabase_manager.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'mfk_sensor_channel',
      initialNotificationTitle: 'MFK Sensor',
      initialNotificationContent: 'Data collection starting...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
  service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  developer.log('🌙 BackgroundService: iOS background mode');
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // ⭐️ SUPABASE INICIALIZÁLÁS A HÁTTÉRBEN
  try {
    developer.log('🔄 BackgroundService: Initializing Supabase...');
    await Supabase.initialize(
      url: 'https://yuamroqhxrflusxeyylp.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1YW1yb3FoeHJmbHVzeGV5eWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU4NjA2ODgsImV4cCI6MjA2MTQzNjY4OH0.GOzgzWLxQnT6YzS8z2D4OKrsHkBnS55L7oRTMsEKs8U',
    );
    developer.log('✅ BackgroundService: Supabase initialized successfully');
  } catch (e) {
    developer.log('❌ BackgroundService: Supabase initialization error: $e');
    // ⭐️ NE ÁLLJUNK LE, FOLYTATSUK ADATGYYŰJTÉST
  }

  developer.log('🚀 BackgroundService: Starting service...');

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stop').listen((event) {
    service.stopSelf();
  });

  final bleManager = BLEManager();
  final locationManager = LocationManager();
  final dbManager = DatabaseManager();
  final supabaseManager = SupabaseManager();

  String latestBLEData = '';
  Position? latestLocation;
  bool isConnected = false;
  Timer? saveTimer;
  Timer? syncTimer;
  double saveInterval = 2.0;

  // ⭐️ CONNECTIVITY INICIALIZÁLÁS
  Future.delayed(const Duration(seconds: 3), () async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      isConnected = connectivityResult != ConnectivityResult.none;
      developer.log('📡 BackgroundService: Initial connectivity: $connectivityResult, connected: $isConnected');

      if (isConnected) {
        developer.log('🔄 BackgroundService: Internet available, checking for unsynced data...');
        await _syncUnsyncedData(dbManager, supabaseManager);
      }
    } catch (e) {
      developer.log('❌ BackgroundService: Initial connectivity check error: $e');
    }
  });

  // ⭐️ CONNECTIVITY VÁLTOZÁSOK FIGYELÉSE
  Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
    try {
      final result = results.isNotEmpty ? results.last : ConnectivityResult.none;
      final wasConnected = isConnected;
      isConnected = result != ConnectivityResult.none;
      developer.log('📡 BackgroundService: Connectivity changed: $result, connected: $isConnected');

      // ⭐️ HA VISSZATÉRT AZ INTERNET, AZONNAL SZINKRONIZÁLJUNK
      if (isConnected && !wasConnected) {
        developer.log('🎉 BackgroundService: Internet restored, immediate sync!');
        await _syncUnsyncedData(dbManager, supabaseManager);
      }
    } catch (e) {
      developer.log('❌ BackgroundService: Connectivity listener error: $e');
    }
  });

  locationManager.onLocationUpdated.listen((position) {
    latestLocation = position;
    developer.log('📍 BackgroundService: Location updated: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}');
  });

  bleManager.onDisconnected.listen((_) {
    latestBLEData = '';
    developer.log('🔌 BackgroundService: BLE disconnected - data cleared');

    // ⭐️ AZONNALI ÚJRAKAPCSOLÓDÁS
    Future.delayed(const Duration(seconds: 2), () {
      if (latestBLEData.isEmpty) {
        developer.log('🔄 BackgroundService: Auto-reconnecting BLE...');
        bleManager.startScanning();
      }
    });
  });

  bleManager.onDataReceived.listen((data) {
    if (data.isNotEmpty &&
        data.contains('=') &&
        (data.contains('SEN55') || data.contains('SEN66'))) {
      latestBLEData = data;
      developer.log('📱 BackgroundService: Valid BLE data received: "$data"');
    } else if (data.isEmpty) {
      latestBLEData = '';
      developer.log('📱 BackgroundService: BLE data cleared');
    }
  });

  // ⭐️ SZOLGÁLTATÁSOK INDÍTÁSA
  Future.delayed(const Duration(seconds: 2), () {
    developer.log('🔍 BackgroundService: Starting Bluetooth scan...');
    bleManager.startScanning();
    locationManager.startUpdatingLocation();
    developer.log('📍 BackgroundService: Starting location updates...');
  });

  // ⭐️ MENTÉSI TIMER
  void startSaveTimer() {
    saveTimer?.cancel();
    saveTimer = Timer.periodic(Duration(seconds: saveInterval.toInt()), (timer) async {
      developer.log('⏰ Save Timer: Checking conditions...');
      developer.log('⏰ Save Timer: BLE - "${latestBLEData.isEmpty ? "empty" : "available"}", Location - ${latestLocation != null ? "available" : "null"}');

      bool hasValidBLEData = latestBLEData.isNotEmpty &&
          !latestBLEData.contains('Searching') &&
          (latestBLEData.contains('SEN55') || latestBLEData.contains('SEN66')) &&
          latestBLEData.contains('=');

      bool hasValidLocation = latestLocation != null;

      if (hasValidBLEData && hasValidLocation) {
        developer.log('💾 Save Timer: All conditions met, saving data...');
        await _saveData(dbManager, latestBLEData, latestLocation!);
      } else {
        developer.log('⏰ Save Timer: Skipping save - BLE: ${hasValidBLEData ? "OK" : "NO"}, GPS: ${hasValidLocation ? "OK" : "NO"}');
      }

      // UI frissítés
      final unsyncedCount = (await dbManager.getUnsynced()).length;

      String bleStatus;
      if (latestBLEData.isEmpty) {
        bleStatus = 'Searching for device...';
      } else if (!latestBLEData.contains('=')) {
        bleStatus = 'Connecting to device...';
      } else {
        bleStatus = latestBLEData;
      }

      String locationStatus = latestLocation != null
          ? 'POINT(${latestLocation!.longitude.toStringAsFixed(6)} ${latestLocation!.latitude.toStringAsFixed(6)})'
          : 'Waiting for GPS...';

      service.invoke('update', {
        'ble_data': bleStatus,
        'location': locationStatus,
        'unsynced_count': unsyncedCount,
      });
    });
  }

  // ⭐️ SZINKRONIZÁLÁSI TIMER (30 másodpercenként)
  void startSyncTimer() {
    syncTimer?.cancel();
    syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      developer.log('🔄 Sync Timer: Checking for sync...');

      if (isConnected) {
        developer.log('🔄 Sync Timer: Internet available, syncing...');
        await _syncUnsyncedData(dbManager, supabaseManager);
      } else {
        developer.log('🔄 Sync Timer: No internet, skipping sync');
      }
    });
  }

  service.on('setSaveInterval').listen((event) {
    if (event != null && event['interval'] is double) {
      saveInterval = event['interval'];
      startSaveTimer();
      developer.log('✅ BackgroundService: Save interval set to $saveInterval seconds');
    }
  });

  // ⭐️ TIMEREK INDÍTÁSA
  startSaveTimer();
  startSyncTimer();

  developer.log('✅ BackgroundService: All systems started successfully');
}

Map<String, double> _parseBleData(String rawData) {
  final cleaned = rawData.replaceFirst(RegExp(r'^[^:]*: '), '').trim();
  final entries = cleaned.split(', ');
  Map<String, double> parsed = {};
  for (var entry in entries) {
    final parts = entry.split('=');
    if (parts.length == 2) {
      final key = parts[0].trim();
      final value = double.tryParse(parts[1].trim()) ?? 0.0;
      parsed[key] = value;
    }
  }
  return parsed;
}

Future<void> _saveData(DatabaseManager dbManager, String data, Position location) async {
  try {
    final parsed = _parseBleData(data);
    final now = DateTime.now().toIso8601String();

    final newData = AirQuality(
      timestamp: now,
      location: 'POINT(${location.longitude} ${location.latitude})',
      pm1_0: parsed['PM1'] ?? 0.0,
      pm2_5: parsed['PM2.5'] ?? 0.0,
      pm4_0: parsed['PM4'] ?? 0.0,
      pm10_0: parsed['PM10'] ?? 0.0,
      humidity: parsed['Humidity'] ?? 0.0,
      temperature: parsed['Temp'] ?? 0.0,
      voc: parsed['VOC'] ?? 0.0,
      nox: parsed['NOx'] ?? 0.0,
      co2: parsed['CO2'] ?? 0.0,
    );

    final int id = await dbManager.insert(newData);
    newData.id = id;
    developer.log('💾 BackgroundService: Data saved locally! ID: $id, Time: $now');
  } catch (e) {
    developer.log('❌ BackgroundService Save error: $e');
  }
}

Future<void> _syncUnsyncedData(DatabaseManager dbManager, SupabaseManager supabaseManager) async {
  try {
    developer.log('🔄 BackgroundService: Checking for unsynced data...');
    final List<AirQuality> unsynced = await dbManager.getUnsynced();
    developer.log('📊 BackgroundService: Found ${unsynced.length} unsynced records');

    if (unsynced.isNotEmpty) {
      developer.log('🚀 BackgroundService: Starting sync process with ${unsynced.length} records...');

      // ⭐️ RÉSZLETEZETT ADAT ELLENŐRZÉS
      for (var data in unsynced.take(3)) { // Csak az első 3-at logoljuk
        developer.log('📋 BackgroundService: Data sample - Time: ${data.timestamp}, Location: ${data.location}');
      }

      await supabaseManager.syncData(unsynced);

      // ⭐️ ELLENŐRZÉS A SZINKRONIZÁLÁS UTÁN
      final remainingUnsynced = await dbManager.getUnsynced();
      developer.log('✅ BackgroundService: Sync process completed. Remaining unsynced: ${remainingUnsynced.length}');
    } else {
      developer.log('📊 BackgroundService: No unsynced records to sync');
    }
  } catch (e) {
    developer.log('❌ BackgroundService: Sync error: $e');
    developer.log('❌ BackgroundService: Full error: ${e.toString()}');
  }
}
