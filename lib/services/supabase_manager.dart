import 'database_manager.dart';
import 'dart:developer' as developer;
import 'background_service.dart';

class SupabaseManager {
  static final SupabaseManager _instance = SupabaseManager._internal();
  factory SupabaseManager() => _instance;
  SupabaseManager._internal();

  Future<void> syncData(List<AirQuality> dataList) async {
    if (dataList.isEmpty) return;

    developer.log('SupabaseManager: Syncing ${dataList.length} records');

    try {
      // MÓDOSÍTOTT: NEM csak az 'id' és 'uploaded' eltávolítása, hanem minden lokális mező
      final maps = dataList.map((data) {
        final map = data.toMap();
        // Távolítsuk el az összes olyan mezőt, ami nem létezik a Supabase táblában
        map.remove('id');
        map.remove('uploaded');
        // Biztosítsuk, hogy csak a Supabase táblában létező mezőket küldjük
        return {
          'timestamp': map['timestamp'],
          'location': map['location'],
          'pm1_0': map['pm1_0'],
          'pm2_5': map['pm2_5'],
          'pm4_0': map['pm4_0'],
          'pm10_0': map['pm10_0'],
          'humidity': map['humidity'],
          'temperature': map['temperature'],
          'voc': map['voc'],
          'nox': map['nox'],
          'co2': map['co2'],
        };
      }).toList();

      developer.log('🔄 Sending ${maps.length} records to Supabase');
      developer.log('📦 First record: ${maps.first}');

      final restSuccess = await SupabaseRestClient.insertData(maps);

      if (restSuccess) {
        final ids = dataList.where((e) => e.id != null).map((e) => e.id!).toList();
        if (ids.isNotEmpty) {
          await DatabaseManager().markAsUploaded(ids);
          developer.log('✅ Successfully synced ${dataList.length} records via REST API');
        }
      } else {
        developer.log('❌ REST API sync failed');
      }

    } catch (e) {
      developer.log('❌ Sync error: $e');
    }
  }
}