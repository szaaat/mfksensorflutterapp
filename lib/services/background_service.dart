import 'dart:async';
import 'dart:ui';
import 'dart:developer' as developer;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // HIÁNYZÓ IMPORT
import 'package:mfk_sensor/utils/time_helper.dart';
// Saját managereid importálása
import 'package:mfk_sensor/services/ble_manager.dart';
import 'package:mfk_sensor/services/location_manager.dart';
import 'package:mfk_sensor/services/database_manager.dart';
import 'package:mfk_sensor/services/supabase_manager.dart';
import 'dart:convert';
import 'dart:io';

// Fő inicializáló függvény, amit a main.dart-ból hívunk meg
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'mfk_sensor_channel',
      initialNotificationTitle: 'MFK Sensor',
      initialNotificationContent: 'Adatgyűjtés indul...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: (ServiceInstance service) async {
        // iOS-en a háttérben való futás engedélyezése
        return true;
      },
    ),
  );
  service.startService();
}

// Ezt a pragma-t kötelező megadni, hogy a kód optimalizálás során ne legyen eltávolítva.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  developer.log('🎯 BackgroundService: onStart called - Initializing services');

  // SUPABASE INICIALIZÁLÁS - EXTRA OPTIONSEKKEL
  // SUPABASE INICIALIZÁLÁS - EXTRA OPTIONSEKKEL
  try {
    developer.log('🔍 BackgroundService: Initializing Supabase with options...');

    await Supabase.initialize(
      url: 'https://yuamroqhxrflusxeyylp.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1YW1yb3FoeHJmbHVzeGV5eWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU4NjA2ODgsImV4cCI6MjA2MTQzNjY4OH0.GOzgzWLxQnT6YzS8z2D4OKrsHkBnS55L7oRTMsEKs8U',

    );


    // --- JAVÍTOTT RÉSZ KEZDETE ---

    // Ellenőrizzük, hogy tényleg működik-e
    // A lekérdezés vagy lefut, vagy kivételt dob, amit a külső catch elkap.
    await Supabase.instance.client.from('air_quality').select('id').limit(1);

    // Ha a program eljutott idáig, az azt jelenti, hogy a hívás sikeres volt.
    developer.log(
        '✅ BackgroundService: Supabase initialized and tested successfully');

    // --- JAVÍTOTT RÉSZ VÉGE ---

  } on PostgrestException catch (e) {
    // Specifikus Supabase hiba elkapása
    developer.log(
        '❌ BackgroundService: Supabase PostgrestException: ${e.message}');
    // Megpróbáljuk tovább futni, de csak adatgyűjtéssel, szinkronizálás nélkül
  } catch (e) {
    // Általános inicializálási hiba elkapása
    developer.log('❌ BackgroundService: Supabase initialization failed: $e');
    // Megpróbáljuk tovább futni, de csak adatgyűjtéssel, szinkronizálás nélkül
  }

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
  }

  final bleManager = BLEManager();
  final locationManager = LocationManager();
  final dbManager = DatabaseManager();
  final supabaseManager = SupabaseManager();

  developer.log('✅ BackgroundService: Managers created');

  String latestBLEData = '';
  Position? latestLocation;
  bool isConnected = false;
  double interval = 2.0;

  bool _bleConnected = false;
  String _bleStatus = "Searching...";

  // AZONNALI SZOLGÁLTATÁS INDÍTÁS
  developer.log('🚀 BackgroundService: Starting BLE and GPS services...');

  // BLE indítása
  try {
    developer.log('📱 Starting BLE services...');
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
    developer.log('📱 Bluetooth state: $state');

    if (state == BluetoothAdapterState.on) {
      await bleManager.startScanning();
      developer.log('✅ BLE scanning started successfully');
    } else {
      developer.log('❌ Bluetooth not available, waiting for state change...');
      FlutterBluePlus.adapterState.listen((newState) async {
        if (newState == BluetoothAdapterState.on) {
          developer.log('📱 Bluetooth turned on, starting scan');
          await bleManager.startScanning();
        }
      });
    }
  } catch (e) {
    developer.log('❌ BLE service start error: $e');
  }

  // GPS indítása
  try {
    developer.log('📍 Starting GPS services...');
    await locationManager.startUpdatingLocation();
    developer.log('✅ GPS services started');
  } catch (e) {
    developer.log('❌ GPS service start error: $e');
  }

  // Hálózati kapcsolat figyelése
  Connectivity().onConnectivityChanged.listen((results) {
    final result = results.isNotEmpty ? results.last : ConnectivityResult.none;
    isConnected = result != ConnectivityResult.none;
    developer.log('📡 Network connectivity: $isConnected');
  });

  // Location updates
  locationManager.onLocationUpdated.listen((position) {
    latestLocation = position;
    developer.log('📍 Location updated: ${position.latitude}, ${position.longitude}');
  });

  // BLE data updates
  bleManager.onDataReceived.listen((data) {
    if (data.isNotEmpty) {
      latestBLEData = data;
      _bleConnected = true;
      _bleStatus = "Connected"; // Állapot beállítása
      developer.log('📱 BLE data received: "$data"');
    }
  });

  bleManager.onDisconnected.listen((_) {
    latestBLEData = '';
    _bleConnected = false;
    _bleStatus = "Disconnected - Reconnecting..."; // Állapot beállítása
    developer.log('🔌 BLE device disconnected');
  });

  // Timer indítása adatgyűjtéshez
  // JAVÍTOTT TIMER RÉSZ:
  Timer.periodic(Duration(seconds: interval.toInt()), (timer) async {
    developer.log('⏰ Timer tick - BLE: "${latestBLEData.isEmpty ? "empty" : latestBLEData}", GPS: ${latestLocation != null ? "OK" : "null"}');

    // BLE állapot ellenőrzés
    if (!_bleConnected && latestBLEData.isEmpty) {
      _bleStatus = "Searching for device...";
    }

    // Adatmentés logika (ez a rész változatlan)
    if (latestBLEData.isNotEmpty &&
        !latestBLEData.contains('Searching') &&
        (latestBLEData.contains('SEN55') || latestBLEData.contains('SEN66')) &&
        latestLocation != null) {

      developer.log('💾 Saving data to local database...');
      await _saveData(dbManager, latestBLEData, latestLocation!);
    }

    // SZINKRONIZÁLÁS (ez a rész is változatlan)
    if (timer.tick % 5 == 0) {
      try {
        if (isConnected) {
          developer.log('🔄 Starting sync process...');
          await _syncUnsyncedData(dbManager, supabaseManager);
        } else {
          developer.log('📡 No network connection, skipping sync');
        }
      } catch (e) {
        developer.log('⚠️ Sync error: $e');
      }
    }

    // UI frissítés kibővített adatokkal
    // UI frissítés kibővített adatokkal
    final unsyncedCount = (await dbManager.getUnsynced()).length;
    service.invoke('update', {
      'ble_data': latestBLEData.isNotEmpty ? latestBLEData : _bleStatus,
      'location': latestLocation != null
          ? 'POINT(${latestLocation!.longitude.toStringAsFixed(
          6)} ${latestLocation!.latitude.toStringAsFixed(6)})'
          : 'Waiting for GPS...',
      'unsynced_count': unsyncedCount,
      'ble_status': _bleStatus,
      // Ez maradhat, a részletesebb állapotüzenethez

      // JAVÍTÁS: A 'ble_connected' logikája sokkal pontosabb lett.
      // Akkor tekintjük csatlakoztatottnak, ha az adat nem üres, nem csak "keres",
      // és tartalmazza az eszköz nevét.
      'ble_connected': latestBLEData.isNotEmpty &&
          !latestBLEData.contains('Searching') &&
          (latestBLEData.contains('SEN55') || latestBLEData.contains('SEN66')),
    });
  });

  developer.log('🎉 BackgroundService: Fully initialized and running');
}

// -----------------------------------------------------------------------------
// Segédfüggvények
// -----------------------------------------------------------------------------

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
  final parsed = _parseBleData(data);
  final nowUtcString = DateTime.now().toUtcIsoString();

  // JAVÍTOTT RÉSZ: pontosabb formázás
  final newData = AirQuality(
    timestamp: nowUtcString, // Explicit UTC
    location: 'POINT(${location.longitude} ${location.latitude})', // Helyes sorrend
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

  try {
    final int id = await dbManager.insert(newData);
    newData.id = id;
    developer.log('✅ BackgroundService: Data saved locally! ID: $id');
    developer.log('📍 Location: ${newData.location}');
    developer.log('🕒 Timestamp (UTC): ${newData.timestamp}');
  } catch (e) {
    developer.log('❌ BackgroundService Save error: $e');
  }
}

Future<void> _syncUnsyncedData(DatabaseManager dbManager,
    SupabaseManager supabaseManager) async {
  final List<AirQuality> unsynced = await dbManager.getUnsynced();
  if (unsynced.isNotEmpty) {
    developer.log(
        'BackgroundService: Found ${unsynced.length} records to sync.');
    await supabaseManager.syncData(unsynced);
    developer.log('BackgroundService: Sync complete.');
  }
}
// Új osztály a background_service.dart fájlba
class SupabaseRestClient {
  static const String baseUrl = 'https://yuamroqhxrflusxeyylp.supabase.co';
  static const String apiKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1YW1yb3FoeHJmbHVzeGV5eWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU4NjA2ODgsImV4cCI6MjA2MTQzNjY4OH0.GOzgzWLxQnT6YzS8z2D4OKrsHkBnS55L7oRTMsEKs8U';

  static Future<bool> insertData(List<Map<String, dynamic>> data) async {
    try {
      developer.log('🔗 SupabaseRestClient: Sending ${data.length} records');

      // KISEBB KÖTEGEK - max 50 rekord egyszerre
      const maxBatchSize = 50;
      bool allSuccess = true;

      for (int i = 0; i < data.length; i += maxBatchSize) {
        final end = i + maxBatchSize < data.length ? i + maxBatchSize : data.length;
        final batch = data.sublist(i, end);

        developer.log('📦 Processing batch ${i ~/ maxBatchSize + 1}: ${batch.length} records');

        final success = await _sendBatch(batch);
        if (!success) {
          allSuccess = false;
        }

        // Várjunk egy kicsit a kötegek között
        await Future.delayed(const Duration(milliseconds: 100));
      }

      return allSuccess;
    } catch (e) {
      developer.log('❌ SupabaseRestClient: Batch processing error: $e');
      return false;
    }
  }

  static Future<bool> _sendBatch(List<Map<String, dynamic>> batch) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      final request = await client.postUrl(Uri.parse('$baseUrl/rest/v1/air_quality'));

      request.headers.set('Content-Type', 'application/json');
      request.headers.set('apikey', apiKey);
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.headers.set('Prefer', 'return=minimal');
      request.headers.set('Accept', 'application/json');

      final jsonData = jsonEncode(batch);
      request.write(jsonData);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      developer.log('📡 Batch response: ${response.statusCode}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        developer.log('✅ Batch inserted successfully');
        return true;
      } else {
        developer.log('❌ Batch failed: ${response.statusCode} - $responseBody');

        // További hibaanálízis
        if (responseBody.contains('duplicate key')) {
          developer.log('🔑 DUPLICATE KEY ERROR - possible ID conflict');
        }
        if (responseBody.contains('violates')) {
          developer.log('🚫 CONSTRAINT VIOLATION - check table schema');
        }

        return false;
      }
    } catch (e) {
      developer.log('❌ Batch send error: $e');
      return false;
    }
  }
}