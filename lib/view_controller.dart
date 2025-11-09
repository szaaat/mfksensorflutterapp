import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mfk_sensor/services/database_manager.dart';
import 'package:mfk_sensor/services/supabase_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:developer' as developer;

class ViewController extends StatefulWidget {
  const ViewController({super.key});

  @override
  State<ViewController> createState() => _ViewControllerState();
}

class _ViewControllerState extends State<ViewController> {
  final DatabaseManager _dbManager = DatabaseManager();
  final FlutterBackgroundService _service = FlutterBackgroundService();

  String _latestBLEData = 'Waiting for data...';
  String _latestLocation = 'No GPS data';
  int _unsyncedCount = 0;
  bool _isServiceRunning = true;
  bool _isConnected = false;
  double _saveInterval = 2.0; // Alapértelmezett 2 másodperc

  final Map<String, Color> _dataColors = {
    'PM1': Colors.orange,
    'PM2.5': Colors.red,
    'PM4': Colors.brown,
    'PM10': Colors.purple,
    'Humidity': Colors.blue,
    'Temp': Colors.green,
    'VOC': Colors.yellow,
    'NOx': Colors.grey,
    'CO2': Colors.indigo,
    'default': Colors.black,
  };

  @override
  void initState() {
    super.initState();

    _service.on('update').listen((event) {
      if (!mounted) return;
      developer.log('UI UPDATE received: $event');
      setState(() {
        if (event!.containsKey('ble_data')) {
          final newData = event['ble_data'] ?? 'Searching...';

          if (newData.isEmpty ||
              newData.contains('Searching') ||
              newData.contains('disconnected') ||
              newData.contains('Reconnecting') ||
              (!newData.contains('SEN55') && !newData.contains('SEN66') && !newData.contains('='))) {
            _latestBLEData = 'Searching for device...';
            _isConnected = false;
          } else {
            _latestBLEData = newData;
            _isConnected = true;
          }

          if (_latestBLEData.contains('already stopped')) {
            _latestBLEData = 'Waiting for location permission...';
          }
        }

        if (event.containsKey('ble_connected')) {
          _isConnected = event['ble_connected'];
          if (!_isConnected) {
            _latestBLEData = 'Device disconnected - Reconnecting...';
          }
        }

        if (event.containsKey('location')) {
          _latestLocation = event['location'];
        }

        if (event.containsKey('unsynced_count')) {
          _unsyncedCount = event['unsynced_count'];
        }
      });
    });
  }

  // Az adatok beragadásának megoldása - reseteljük az adatokat kapcsolat megszakadáskor
  void _resetDataOnDisconnect() {
    if (!_isConnected) {
      setState(() {
        _latestBLEData = 'Searching for device...';
      });
    }
  }

  Map<String, double> _parseBleData(String rawData) {
    if (!_isConnected ||
        rawData.isEmpty ||
        rawData.contains('Searching') ||
        rawData.contains('disconnected') ||
        (!rawData.contains('SEN55') && !rawData.contains('SEN66'))) {
      return {};
    }

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

  void _setSaveInterval(double interval) {
    setState(() {
      _saveInterval = interval;
    });
    _service.invoke("setSaveInterval", {"interval": interval});
    developer.log('✅ ViewController: Save interval set to $interval seconds');
  }

  void _deleteDataButtonTapped() {
    showDialog(
      context: context,
      builder: (BuildContext alertContext) => AlertDialog(
        title: const Text('Delete Data'),
        content: const Text('Are you sure you want to delete all locally stored data?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(alertContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final NavigatorState navigator = Navigator.of(alertContext);
              final String databasesPath = await getDatabasesPath();
              final String path = p.join(databasesPath, 'mfk_sensor.db');
              await deleteDatabase(path);
              if (!mounted) return;
              _showAlert('All data deleted!');
              navigator.pop();
              setState(() => _unsyncedCount = 0);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareDataButtonTapped() async {
    final List<AirQuality> allData = await _dbManager.getUnsynced();
    final String fileText = allData.map((data) => '''
Timestamp: ${data.timestamp} | Location: ${data.location}
PM1.0: ${data.pm1_0}, PM2.5: ${data.pm2_5}, PM4.0: ${data.pm4_0}, PM10.0: ${data.pm10_0}
Humidity: ${data.humidity}, Temp: ${data.temperature}, VOC: ${data.voc}, NOx: ${data.nox}, CO2: ${data.co2}
''').join('\n\n');

    final Directory directory = await getTemporaryDirectory();
    final File file = File('${directory.path}/sensor_data_share.txt');
    await file.writeAsString(fileText.isEmpty ? 'No data to share' : fileText);
    Share.shareXFiles([XFile(file.path)], text: 'MFK Sensor Data');
  }

  void _showMapTapped() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Map')),
          body: WebViewWidget(
            controller: WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..loadRequest(Uri.parse('https://szaaat.github.io/mfksensor/map.html')),
          ),
        ),
      ),
    );
  }

  void _showAlert(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Information'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Segédfüggvény a címkék rövidítésére
  String _getShortLabel(String label) {
    switch (label) {
      case 'PM2.5':
        return 'PM2.5';
      case 'PM10.0':
        return 'PM10';
      case 'Humidity':
        return 'Humid';
      case 'Temperature':
        return 'Temp';
      case 'VOC':
        return 'VOC';
      case 'NOx':
        return 'NOx';
      case 'CO2':
        return 'CO2';
      default:
        return label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, double> parsedBle = _parseBleData(_latestBLEData);
    final bool hasBLEData = parsedBle.isNotEmpty && _isConnected;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // Aktuális téma alapján színek
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? Colors.black : Colors.grey[100];
    final cardColor = isDark ? Colors.grey[900] : Colors.white;
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final statusGood = isDark ? Colors.greenAccent[400] : Colors.green[700];
    final statusWarn = isDark ? Colors.orangeAccent[200] : Colors.orange[700];

    // Automatikus reset kapcsolat megszakadáskor
    _resetDataOnDisconnect();

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Felső logó - kisebb
                Image.asset(
                  'assets/images/mfk_logo.png',
                  height: isLandscape ? 35 : 50,
                  fit: BoxFit.contain,
                  color: isDark ? Colors.white70 : null,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: isLandscape ? 35 : 50,
                    child: Center(
                      child: Text(
                        'MFK SENSOR',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Kapcsolat állapot - kisebb
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? (isDark ? Colors.green.withOpacity(0.2) : Colors.green[100])
                        : (isDark ? Colors.orange.withOpacity(0.2) : Colors.orange[100]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _isConnected ? '✅ Connected to Sensor' : '🔄 Searching for Sensor...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isConnected ? statusGood : statusWarn,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Küldés sűrűségének beállítása
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black45 : Colors.black12,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Data Collection Interval',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildIntervalButton(2, '2s'),
                          _buildIntervalButton(10, '10s'),
                          _buildIntervalButton(60, '60s'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Szenzoradatok - kisebb dobozokkal
                if (hasBLEData)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = isLandscape ? 4 : 3;
                      final childAspectRatio = isLandscape ? 0.9 : 0.8;

                      return GridView.count(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: childAspectRatio,
                        children: parsedBle.entries.map((entry) {
                          final color = _dataColors[entry.key] ?? _dataColors['default']!;
                          return Container(
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark ? Colors.black45 : Colors.black12,
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                )
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _getShortLabel(entry.key),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.value.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _isConnected ? 'Processing sensor data...' : 'Waiting for sensor connection...',
                      style: TextStyle(
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        color: textColor.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 16),

                // Gombok - kisebbek
                if (hasBLEData) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _showMapTapped,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.map, size: 16),
                        label: const Text('Map', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _shareDataButtonTapped,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.share, size: 16),
                        label: const Text('Share', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _deleteDataButtonTapped,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete Data', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 16),
                ],

                // Szinkronizálási információ - kisebb
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black45 : Colors.black12,
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _unsyncedCount == 0 ? Icons.cloud_done : Icons.cloud_upload,
                        color: _unsyncedCount == 0 ? Colors.green : Colors.orange,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _unsyncedCount == 0 ? 'All data synced' : '$_unsyncedCount waiting',
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Alsó logó - kisebb
                Image.asset(
                  'assets/images/emnl_logo.png',
                  height: isLandscape ? 35 : 40,
                  fit: BoxFit.contain,
                  color: isDark ? Colors.white70 : null,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: isLandscape ? 35 : 40,
                    child: Center(
                      child: Text(
                        'EMNL',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Intervallum gomb építése
  Widget _buildIntervalButton(int seconds, String label) {
    final isSelected = _saveInterval == seconds;
    return GestureDetector(
      onTap: () => _setSaveInterval(seconds.toDouble()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (Theme.of(context).brightness == Brightness.dark ? Colors.blue[700] : Colors.blue)
              : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[300]),
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: Colors.blueAccent, width: 2) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}