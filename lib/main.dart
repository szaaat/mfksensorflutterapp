import 'package:flutter/material.dart';
import 'package:mfk_sensor/app_delegate.dart';
import 'package:mfk_sensor/view_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mfk_sensor/services/background_service.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Engedélyek kérése
  await _requestPermissions();

  // Supabase inicializálás (fő izolátumban)
  await Supabase.initialize(
    url: 'https://yuamroqhxrflusxeyylp.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1YW1yb3FoeHJmbHVzeGV5eWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU4NjA2ODgsImV4cCI6MjA2MTQzNjY4OH0.GOzgzWLxQnT6YzS8z2D4OKrsHkBnS55L7oRTMsEKs8U',
  );

  // Háttérszolgáltatás indítása
  await initializeService();

  runApp(const MFKSensorApp());
}

Future<void> _requestPermissions() async {
try {
// Bluetooth engedélyek
await Permission.bluetooth.request();
await Permission.bluetoothScan.request();
await Permission.bluetoothConnect.request();

// Helymeghatározás engedélyek
await Permission.location.request();
await Permission.locationAlways.request();

print('✅ Permissions requested successfully');
} catch (e) {
print('❌ Permission request error: $e');
}
}

class MFKSensorApp extends StatelessWidget {
const MFKSensorApp({super.key});

@override
Widget build(BuildContext context) {
return MaterialApp(
title: 'MFK Sensor',
theme: ThemeData(
primarySwatch: Colors.blue,
visualDensity: VisualDensity.adaptivePlatformDensity,
),
home: const ViewController(),
navigatorObservers: [AppDelegate.routeObserver],
);
}
}
