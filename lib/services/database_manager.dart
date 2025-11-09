import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:developer' as developer;

class AirQuality {
  int? id;
  String timestamp;
  String location; // ÚJ: POINT(longitude latitude)
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
            location TEXT NOT NULL,  -- ÚJ: location TEXT
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
    return await dbClient.insert('air_quality', data.toMap());
  }

  Future<List<AirQuality>> getUnsynced() async {
    final dbClient = await db;
    final maps = await dbClient.query(
      'air_quality',
      where: 'uploaded = ?',
      whereArgs: [0],
    );
    return maps.map((map) => AirQuality.fromMap(map)).toList();
  }

  Future<void> markAsUploaded(List<int> ids) async {
    if (ids.isEmpty) return;

    final dbClient = await db;
    try {
      // JAVÍTOTT: használjunk rawQuery-t vagy a megfelelő update szintaxist
      final placeholders = List.filled(ids.length, '?').join(',');
      await dbClient.rawUpdate('''
      UPDATE air_quality 
      SET uploaded = 1 
      WHERE id IN ($placeholders)
    ''', ids);

      developer.log('DatabaseManager: Marked ${ids.length} records as uploaded');
    } catch (e) {
      developer.log('❌ DatabaseManager: Error marking records as uploaded: $e');
      rethrow;
    }
  }

// Új metódus: adatbázis állapot ellenőrzése
  Future<Map<String, dynamic>> getDatabaseStatus() async {
    final dbClient = await db;
    try {
      final totalCount = Sqflite.firstIntValue(
          await dbClient.rawQuery('SELECT COUNT(*) FROM air_quality')
      ) ?? 0;

      final unsyncedCount = Sqflite.firstIntValue(
          await dbClient.rawQuery('SELECT COUNT(*) FROM air_quality WHERE uploaded = 0')
      ) ?? 0;

      return {
        'total': totalCount,
        'unsynced': unsyncedCount,
        'synced': totalCount - unsyncedCount
      };
    } catch (e) {
      developer.log('❌ DatabaseManager: Error getting database status: $e');
      return {'total': 0, 'unsynced': 0, 'synced': 0};
    }
  }

  // In database_manager.dart
  Future<void> clearAllAirQualityData() async {
    final dbClient = await db; // JAVÍTÁS: használd a 'db' gettert
    await dbClient.delete('air_quality');
  }
  Future<void> close() async {
    final dbClient = await db;
    await dbClient.close();
  }
}