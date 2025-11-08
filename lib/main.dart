import 'package:flutter/cupertino.dart';
import 'package:mfk_sensor/app_delegate.dart';
import 'package:mfk_sensor/view_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mfk_sensor/services/background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://yuamroqhxrflusxeyylp.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1YW1yb3FoeHJmbHVzeGV5eWxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU4NjA2ODgsImV4cCI6MjA2MTQzNjY4OH0.GOzgzWLxQnT6YzS8z2D4OKrsHkBnS55L7oRTMsEKs8U',
  );

  await initializeService();

  runApp(const MFKSensorApp());
}

class MFKSensorApp extends StatelessWidget {
  const MFKSensorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // A 'const' kulcsszó el lett távolítva a CupertinoApp elől
    return CupertinoApp(
      title: 'MFK Sensor',
      theme: const CupertinoThemeData( // A belső widgetek maradhatnak const, ha lehet
        brightness: Brightness.light,
        primaryColor: CupertinoColors.systemBlue,
      ),
      home: const ViewController(),
      // A ViewController is lehet const, ha a konstruktora az
      navigatorObservers: [AppDelegate.routeObserver],
    );
  }
}
