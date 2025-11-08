import 'package:flutter/cupertino.dart';
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
  double _saveInterval = 2.0;
  String _syncStatus = 'Synchronized';

  final Map<String, Color> _dataColors = {
    'PM1': CupertinoColors.systemOrange,
    'PM2.5': CupertinoColors.systemRed,
    'PM4': CupertinoColors.systemBrown,
    'PM10': CupertinoColors.systemPurple,
    'Humidity': CupertinoColors.systemBlue,
    'Temp': CupertinoColors.systemGreen,
    'VOC': CupertinoColors.systemYellow,
    'NOx': CupertinoColors.systemGrey,
    'CO2': CupertinoColors.systemIndigo,
    'default': CupertinoColors.label,
  };

  @override
  void initState() {
    super.initState();

    _service.on('update').listen((event) {
      if (!mounted) return;
      developer.log('UI UPDATE received: $event');
      setState(() {
        if (event!.containsKey('ble_data')) {
          _latestBLEData = event['ble_data'] ?? 'Searching...';

          if (_latestBLEData.isEmpty ||
              _latestBLEData.contains('Searching') ||
              (!_latestBLEData.contains('SEN55') && !_latestBLEData.contains('SEN66'))) {
            _latestBLEData = 'Searching... (no connection)';
          }
        }

        if (event.containsKey('location')) {
          _latestLocation = event['location'];
        }

        if (event.containsKey('unsynced_count')) {
          _unsyncedCount = event['unsynced_count'];
        }

        _updateSyncStatus();
      });
    });

    _service.isRunning().then((v) {
      developer.log('ViewController: Background service is ${v ? "running" : "NOT running"}');
      setState(() => _isServiceRunning = v);

      if (!v) {
        developer.log('ViewController: Attempting to restart background service...');
        _service.startService();
      }
    });
  }

  void _updateSyncStatus() {
    _syncStatus = _unsyncedCount == 0
        ? 'Synchronized ${DateTime.now().toString().substring(11, 16)}'
        : 'Offline - $_unsyncedCount data waiting';
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

  void _setSaveInterval(double interval) {
    setState(() {
      _saveInterval = interval;
    });
    _service.invoke("setSaveInterval", {"interval": interval});
    developer.log('✅ ViewController: Save interval set to $interval seconds');
  }

  void _deleteDataButtonTapped() {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Delete Data'),
        message: const Text('Are you sure you want to delete all locally stored data?'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              final String databasesPath = await getDatabasesPath();
              final String path = p.join(databasesPath, 'mfk_sensor.db');
              await deleteDatabase(path);
              if (!mounted) return;
              _showAlert('All data deleted!');
              _updateSyncStatus();
              setState(() => _unsyncedCount = 0);
            },
            isDestructiveAction: true,
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showMapTapped() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Map'),
          ),
          child: WebViewWidget(
            controller: WebViewController()
              ..setJavaScriptMode(JavaScriptMode.unrestricted)
              ..loadRequest(Uri.parse('https://szaaat.github.io/mfksensor/map.html')),
          ),
        ),
      ),
    );
  }

  void _showAlert(String message) {
    showCupertinoDialog(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('Information'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _createDataRow(String label, String value, {Color color = CupertinoColors.label}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CupertinoColors.separator, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _createStatusIndicator(String status, bool isActive) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isActive ? CupertinoIcons.checkmark_alt_circle_fill : CupertinoIcons.xmark_circle_fill,
          color: isActive ? CupertinoColors.systemGreen : CupertinoColors.systemRed,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(
          status,
          style: TextStyle(
            fontSize: 14,
            color: isActive ? CupertinoColors.systemGreen : CupertinoColors.systemRed,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // MANUAL SYNC button
  Widget _createManualSyncButton() {
    return CupertinoButton(
      onPressed: () async {
        developer.log('🔄 Manual sync triggered');
        final dbManager = DatabaseManager();
        final supabaseManager = SupabaseManager();
        final unsynced = await dbManager.getUnsynced();
        developer.log('📊 Manual sync: ${unsynced.length} records found');

        if (unsynced.isNotEmpty) {
          _showAlert('Sync started: ${unsynced.length} data');
          await supabaseManager.syncData(unsynced);
          final updatedUnsynced = await dbManager.getUnsynced();
          setState(() {
            _unsyncedCount = updatedUnsynced.length;
            _updateSyncStatus();
          });
          _showAlert('Sync completed. Remaining: $_unsyncedCount data');
        } else {
          _showAlert('No unsynchronized data');
        }
      },
      color: CupertinoColors.systemBlue,
      child: const Text('Manual Sync'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, double> parsedBle = _parseBleData(_latestBLEData);
    final bool hasBLEData = parsedBle.isNotEmpty &&
        _latestBLEData.contains('=') &&
        (_latestBLEData.contains('SEN55') || _latestBLEData.contains('SEN66'));
    final bool hasGPS = _latestLocation != 'No GPS data' && !_latestLocation.contains('Waiting');

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        // ELTÁVOLÍTVA: middle: Text('MFK Sensor'),
        backgroundColor: CupertinoColors.systemBackground,
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top Logo
            Container(
              padding: const EdgeInsets.all(20),
              child: Image.asset(
                'assets/images/mfk_logo.png',
                width: 200,
                height: 50,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                const SizedBox(height: 50, child: Center(child: Text('MFK Logo'))),
              ),
            ),

            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Sensor Data Section
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground,
                        border: Border.all(color: CupertinoColors.separator, width: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          // Status indicators
                          Container(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _createStatusIndicator('GPS', hasGPS),
                                _createStatusIndicator('Bluetooth', hasBLEData),
                                _createStatusIndicator('Service', _isServiceRunning),
                              ],
                            ),
                          ),

                          // Bluetooth connection status
                          if (!hasBLEData)
                            Container(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Bluetooth connecting...',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: CupertinoColors.systemOrange,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),

                          // Sensor data rows
                          if (hasBLEData) ...[
                            _createDataRow('PM1.0', '${parsedBle['PM1']?.toStringAsFixed(1) ?? '0.0'}', color: _dataColors['PM1']!),
                            _createDataRow('PM2.5', '${parsedBle['PM2.5']?.toStringAsFixed(1) ?? '0.0'}', color: _dataColors['PM2.5']!),
                            _createDataRow('PM4.0', '${parsedBle['PM4']?.toStringAsFixed(1) ?? '0.0'}', color: _dataColors['PM4']!),
                            _createDataRow('PM10.0', '${parsedBle['PM10']?.toStringAsFixed(1) ?? '0.0'}', color: _dataColors['PM10']!),
                            _createDataRow('Humidity', '${parsedBle['Humidity']?.toStringAsFixed(1) ?? '0.0'}%', color: _dataColors['Humidity']!),
                            _createDataRow('Temperature', '${parsedBle['Temp']?.toStringAsFixed(1) ?? '0.0'}°C', color: _dataColors['Temp']!),
                            _createDataRow('VOC', '${parsedBle['VOC']?.toStringAsFixed(1) ?? '0.0'}', color: _dataColors['VOC']!),
                            _createDataRow('NOx', '${parsedBle['NOx']?.toStringAsFixed(1) ?? '0.0'}', color: _dataColors['NOx']!),
                            if (parsedBle.containsKey('CO2') && parsedBle['CO2']! > 0)
                              _createDataRow('CO2', '${parsedBle['CO2']?.toStringAsFixed(1) ?? '0.0'}', color: _dataColors['CO2']!),
                          ],

                          // Sync status
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: CupertinoColors.secondarySystemBackground,
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(12),
                                bottomRight: Radius.circular(12),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Saved measurements:'),
                                    Text(
                                      '$_unsyncedCount',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Sync status:'),
                                    Text(
                                      _syncStatus,
                                      style: TextStyle(
                                        color: _unsyncedCount == 0
                                            ? CupertinoColors.systemGreen
                                            : CupertinoColors.systemOrange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Data Collection Frequency - CENTERED
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground,
                        border: Border.all(color: CupertinoColors.separator, width: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Data Collection Frequency',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          CupertinoSlidingSegmentedControl<double>(
                            groupValue: _saveInterval,
                            children: {
                              2.0: const Text('Car\n(2s)'),
                              10.0: const Text('Bike\n(10s)'),
                              60.0: const Text('Walk\n(60s)'),
                            },
                            onValueChanged: (value) {
                              if (value != null) {
                                _setSaveInterval(value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Buttons section
                  SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Manual Sync button
                          _createManualSyncButton(),
                          const SizedBox(height: 12),

                          // Map button
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton.filled(
                              onPressed: _showMapTapped,
                              child: const Text('Open Map'),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Delete Data button
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton(
                              color: CupertinoColors.systemRed,
                              onPressed: _deleteDataButtonTapped,
                              child: const Text('Delete Data'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom spacing for EMNL logo
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 80),
                  ),
                ],
              ),
            ),

            // Bottom EMNL Logo - FIXED AT BOTTOM
            Container(
              padding: const EdgeInsets.all(20),
              child: Image.asset(
                'assets/images/emnl_logo.png',
                width: 200,
                height: 50,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                const SizedBox(height: 50, child: Center(child: Text('EMNL Logo'))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}