import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:developer' as developer;

class AirQuality {
  int? id;
  String timestamp;
  String location;
  double pm1_0;
  double pm2_5;
  double pm4_0;
  double pm10_0;
  double humidity;
  double temperature;
  double voc;
  double nox;
  double co2;
  int uploaded;

  AirQuality({
    this.id,
    required this.timestamp,
    required this.location,
    required this.pm1_0,
    required this.pm2_5,
    required this.pm4_0,
    required this.pm10_0,
    required this.humidity,
    required this.temperature,
    required this.voc,
    required this.nox,
    required this.co2,
    this.uploaded = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp,
      'location': location,
      'pm1_0': pm1_0,
      'pm2_5': pm2_5,
      'pm4_0': pm4_0,
      'pm10_0': pm10_0,
      'humidity': humidity,
      'temperature': temperature,
      'voc': voc,
      'nox': nox,
      'co2': co2,
      'uploaded': uploaded,
    };
  }

  factory AirQuality.fromMap(Map<String, dynamic> map) {
    return AirQuality(
      id: map['id'],
      timestamp: map['timestamp'],
      location: map['location'],
      pm1_0: map['pm1_0'],
      pm2_5: map['pm2_5'],
      pm4_0: map['pm4_0'],
      pm10_0: map['pm10_0'],
      humidity: map['humidity'],
      temperature: map['temperature'],
      voc: map['voc'],
      nox: map['nox'],
      co2: map['co2'],
      uploaded: map['uploaded'],
    );
  }
}

class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  factory DatabaseManager() => _instance;
  DatabaseManager._internal();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'mfk_sensor.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE air_quality (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            location TEXT NOT NULL,
            pm1_0 REAL,
            pm2_5 REAL,
            pm4_0 REAL,
            pm10_0 REAL,
            humidity REAL,
            temperature REAL,
            voc REAL,
            nox REAL,
            co2 REAL,
            uploaded INTEGER DEFAULT 0
          )
        ''');
      },
    );
  }

  Future<int> insert(AirQuality data) async {
    final dbClient = await db;

    // ⭐️ ADAT ÉRVÉNYESSÉGI ELLENŐRZÉS
    if (data.timestamp.isEmpty) {
      data.timestamp = DateTime.now().toIso8601String();
      developer.log('⚠️ DatabaseManager: Empty timestamp, using current time');
    }

    if (data.location.isEmpty) {
      data.location = 'POINT(0 0)';
      developer.log('⚠️ DatabaseManager: Empty location, using default');
    }

    // ⭐️ NUMERIKUS ÉRTÉKEK ELLENŐRZÉSE
    final numericFields = [data.pm1_0, data.pm2_5, data.pm4_0, data.pm10_0, data.humidity, data.temperature, data.voc, data.nox, data.co2];
    for (var value in numericFields) {
      if (value.isNaN || value.isInfinite) {
        developer.log('⚠️ DatabaseManager: Invalid numeric value detected: $value');
      }
    }

    try {
      final int id = await dbClient.insert('air_quality', data.toMap());
      developer.log('💾 DatabaseManager: Data saved with ID: $id');
      return id;
    } catch (e) {
      developer.log('❌ DatabaseManager: Insert error: $e');
      rethrow;
    }
  }


  Future<List<AirQuality>> getUnsynced() async {
    final dbClient = await db;
    final maps = await dbClient.query(
      'air_quality',
      where: 'uploaded = ?',
      whereArgs: [0],
    );

    developer.log('📊 DatabaseManager: Found ${maps.length} unsynced records');

    if (maps.isNotEmpty) {
      for (var i = 0; i < (maps.length < 3 ? maps.length : 3); i++) {
        final map = maps[i];
        developer.log('📄 DatabaseManager: Unsynced record ${i + 1} - ID: ${map['id']}, Time: ${map['timestamp']}');
      }
    } else {
      developer.log('📊 DatabaseManager: No unsynced records found');
    }

    return maps.map((map) => AirQuality.fromMap(map)).toList();
  }

  Future<void> markAsUploaded(List<int> ids) async {
    if (ids.isEmpty) return;
    final dbClient = await db;
    await dbClient.transaction((txn) async {
      await txn.update(
        'air_quality',
        {'uploaded': 1},
        where: 'id IN (${ids.map((_) => '?').join(', ')})',
        whereArgs: ids,
      );
    });
  }

  Future<void> clearAllAirQualityData() async {
    final dbClient = await db;
    await dbClient.delete('air_quality');
  }

  Future<void> close() async {
    final dbClient = await db;
    await dbClient.close();
  }
}