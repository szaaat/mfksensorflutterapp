import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_manager.dart';
import 'dart:developer' as developer;
import 'dart:typed_data';

class SupabaseManager {
  static final SupabaseManager _instance = SupabaseManager._internal();
  factory SupabaseManager() => _instance;

  SupabaseManager._internal() {
    developer.log('✅ SupabaseManager: Instance created');
  }

  SupabaseClient get _client => Supabase.instance.client;

  // ─────────────────────────────────────────────────────────────
  // HELYES EWKB → WKT KONVERZIÓ
  // ─────────────────────────────────────────────────────────────
  String _convertLocationToWkt(dynamic location) {
    try {
      if (location == null) {
        developer.log('📍 Location is null, using default');
        return 'POINT(0 0)';
      }

      final String locationStr = location.toString();

      // Ha már WKT formátumú (POINT(...))
      if (locationStr.toUpperCase().startsWith('POINT(')) {
        developer.log('📍 Location is already WKT: $locationStr');
        return locationStr.contains(';') ? locationStr.split(';').last : locationStr;
      }

      // Ha EWKB hex string
      if (RegExp(r'^[0-9A-Fa-f]{20,}$').hasMatch(locationStr)) {
        developer.log('📍 Converting EWKB to WKT: $locationStr');
        return _ewkbToWkt(locationStr);
      }

      // Egyéb esetek
      developer.log('📍 Unknown location format, using default');
      return 'POINT(0 0)';
    } catch (e) {
      developer.log('❌ Location conversion error: $e');
      return 'POINT(0 0)';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // JAVÍTOTT EWKB → WKT KONVERZIÓ
  // ─────────────────────────────────────────────────────────────
  String _ewkbToWkt(String ewkbHex) {
    try {
      if (ewkbHex.length < 20 || ewkbHex.length % 2 != 0) {
        throw FormatException('Invalid EWKB hex length');
      }

      // Hex string → bytes
      final bytes = Uint8List(ewkbHex.length ~/ 2);
      for (int i = 0; i < ewkbHex.length; i += 2) {
        final hexByte = ewkbHex.substring(i, i + 2);
        bytes[i ~/ 2] = int.parse(hexByte, radix: 16);
      }

      final data = ByteData.view(bytes.buffer);

      // Byte order (1 = little endian)
      final byteOrder = data.getUint8(0);
      final isLittleEndian = byteOrder == 1;
      final endian = isLittleEndian ? Endian.little : Endian.big;

      // Geometry type (4 bytes)
      final type = data.getUint32(1, endian);
      final geometryType = type & 0xFFFF; // Alsó 16 bit a geometry type

      if (geometryType != 1) { // 1 = POINT
        throw FormatException('Not a POINT geometry: $geometryType');
      }

      int offset = 5; // 1 byte order + 4 bytes type

      // SRID check (0x20000000 flag)
      final hasSrid = (type & 0x20000000) != 0;
      if (hasSrid) {
        final srid = data.getUint32(offset, endian);
        developer.log('📍 EWKB SRID: $srid');
        offset += 4;
      }

      // Koordináták kiolvasása (float64)
      if (bytes.length < offset + 16) {
        throw FormatException('Insufficient data for coordinates');
      }

      final double x = data.getFloat64(offset, endian);
      final double y = data.getFloat64(offset + 8, endian);

      final wkt = 'POINT($x $y)';
      developer.log('📍 EWKB → WKT: $wkt');
      return wkt;
    } catch (e) {
      developer.log('❌ EWKB parse error: $e');
      return 'POINT(0 0)';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // JAVÍTOTT SYNC - HASZNÁLD AZ RPC FUNKCIÓT!
  // ─────────────────────────────────────────────────────────────
  Future<void> syncData(List<AirQuality> dataList) async {
    developer.log('🔄 Starting sync with ${dataList.length} records');

    if (dataList.isEmpty) return;

    int successfulUploads = 0;
    final List<int> uploadedIds = [];

    for (int i = 0; i < dataList.length; i++) {
      final data = dataList[i];
      try {
        // Előkészítjük az adatokat
        final map = Map<String, dynamic>.from(data.toMap());
        map.remove('id');

        // ⭐️ FONTOS: Location konverzió WKT-re
        final String wktLocation = _convertLocationToWkt(map['location']);

        // ⭐️ JAVÍTOTT TIMESTAMP: Non-nullable String biztossá tétele
        String timestamp;
        if (map['timestamp'] == null || map['timestamp'].toString().isEmpty) {
          timestamp = DateTime.now().toIso8601String();
        } else {
          timestamp = map['timestamp'].toString(); // .toString() mindig String-et ad vissza
        }

        // Numerikus értékek validálása
        _validateNumericFields(map);

        developer.log('📤 Uploading record ${i + 1}/${dataList.length}');
        developer.log('📍 Location WKT: $wktLocation');
        developer.log('⏰ Timestamp: $timestamp');

        // ⭐️ RPC HÍVÁS a PostGIS függvénnyel
        await _client.rpc('insert_air_quality_record', params: {
          'p_timestamp': timestamp, // Ez most már biztosan String, nem String?
          'p_location_wkt': wktLocation,
          'p_pm1_0': map['pm1_0'] ?? 0.0,
          'p_pm2_5': map['pm2_5'] ?? 0.0,
          'p_pm4_0': map['pm4_0'] ?? 0.0,
          'p_pm10_0': map['pm10_0'] ?? 0.0,
          'p_humidity': map['humidity'] ?? 0.0,
          'p_temperature': map['temperature'] ?? 0.0,
          'p_voc': map['voc'] ?? 0.0,
          'p_nox': map['nox'] ?? 0.0,
          'p_co2': map['co2'] ?? 0.0,
        });

        successfulUploads++;
        if (data.id != null) {
          uploadedIds.add(data.id!);
        }

        developer.log('✅ Record ${i + 1} uploaded successfully');

      } catch (e) {
        developer.log('❌ Failed to upload record ${i + 1}: $e');

        // Fallback: próbáld meg közvetlenül beszúrni (location nélkül)
        try {
          final fallbackMap = Map<String, dynamic>.from(data.toMap());
          fallbackMap.remove('id');
          fallbackMap.remove('location');

          _validateNumericFields(fallbackMap);

          await _client.from('air_quality').insert(fallbackMap);

          successfulUploads++;
          if (data.id != null) {
            uploadedIds.add(data.id!);
          }
          developer.log('✅ Record ${i + 1} uploaded via fallback (no location)');
        } catch (e2) {
          developer.log('❌ Fallback also failed for record ${i + 1}: $e2');
        }
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (uploadedIds.isNotEmpty) {
      await DatabaseManager().markAsUploaded(uploadedIds);
      developer.log('✅ Marked ${uploadedIds.length} records as uploaded locally');
    }

    developer.log('🎉 Sync completed: $successfulUploads/${dataList.length} successful');
  }

  void _validateNumericFields(Map<String, dynamic> map) {
    final fields = ['pm1_0', 'pm2_5', 'pm4_0', 'pm10_0', 'humidity', 'temperature', 'voc', 'nox', 'co2'];

    for (var field in fields) {
      if (map[field] != null && map[field] is double) {
        final value = map[field] as double;
        if (value.isNaN || value.isInfinite) {
          map[field] = 0.0;
        }
      } else if (map[field] == null) {
        map[field] = 0.0;
      }
    }
  }
}