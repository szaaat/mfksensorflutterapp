// lib/services/ble_manager.dart

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:developer' as developer;

// =========================================================================
// KEZDŐDIK A TELJES, ÚJ, ROBOSZTUS OSZTÁLY
// =========================================================================
class BLEManager {
  static final BLEManager _instance = BLEManager._internal();

  factory BLEManager() => _instance;

  BLEManager._internal() {
    // Ezt a részt egyszerűsíthetjük, mert a _periodicScan kezeli a logikát
  }

  // Meglévő és új állapotváltozók
  BluetoothDevice? _connectedDevice;
  bool _isPeriodicScanningActive = false;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  Timer? _reconnectTimer;

  // Stream Controllerek
  final StreamController<String> _dataController = StreamController<
      String>.broadcast();
  final StreamController<void> _disconnectController = StreamController<
      void>.broadcast();

  Stream<String> get onDataReceived => _dataController.stream;

  Stream<void> get onDisconnected => _disconnectController.stream;

  // UUIDs
  final Guid sen66ServiceUUID = Guid("12345678-1234-1234-1234-123456789abc");
  final Guid sen66CharacteristicUUID = Guid(
      "87654321-4321-4321-4321-cba987654321");
  final Guid sen55ServiceUUID = Guid("0000181a-0000-1000-8000-00805f9b34fb");

  // ================================================================
  // NYILVÁNOS METÓDUSOK
  // ================================================================

  Future<void> startScanning() async {
    developer.log('BLEManager: startScanning called');
    if (!await _checkBluetoothState()) return;
    _isPeriodicScanningActive = true;
    _periodicScan();
  }

  Future<void> stopScanning() async {
    _isPeriodicScanningActive = false;
    _reconnectTimer?.cancel();
    _isReconnecting = false;
    await FlutterBluePlus.stopScan();

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _connectedDevice = null;
    developer.log('BLEManager: Scanning stopped completely');
  }

  Future<void> forceReconnect() async {
    developer.log('🔄 BLEManager: Manual reconnect triggered');
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    await Future.delayed(const Duration(milliseconds: 500));
    _handleDisconnection(); // Ez elindítja az újracsatlakozási folyamatot
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _dataController.close();
    _disconnectController.close();
  }

  // ================================================================
  // BELSŐ (PRIVATE) METÓDUSOK
  // ================================================================

  Future<void> _periodicScan() async {
    developer.log('BLEManager: Starting robust periodic scanning...');
    while (_isPeriodicScanningActive && _connectedDevice == null) {
      try {
        developer.log('BLEManager: Starting scan cycle...');
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));

        if (!await _checkBluetoothState()) {
          developer.log('❌ BLEManager: Bluetooth not available, waiting...');
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }

        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 8),
          withServices: [sen55ServiceUUID, sen66ServiceUUID],
        );
        developer.log('BLEManager: Scan started, waiting for results...');

        bool deviceFound = false;
        final subscription = FlutterBluePlus.scanResults.listen((results) {
          for (ScanResult result in results) {
            final name = result.device.platformName;
            if (name.contains('SEN55') || name.contains('SEN66')) {
              if (deviceFound) return; // Már találtunk egyet ebben a ciklusban
              developer.log('🎯 BLEManager: Target device found: $name');
              deviceFound = true;
              _isPeriodicScanningActive =
              false; // Leállítjuk a további ciklusokat
              FlutterBluePlus.stopScan();
              _connectToDevice(result.device);
              return;
            }
          }
        });

        await Future.delayed(const Duration(seconds: 8 + 1));
        await subscription.cancel(); // Mindig leiratkozunk a végén

        if (!deviceFound) {
          developer.log('🔍 BLEManager: No target devices found in this cycle');
        }

        if (_isPeriodicScanningActive && _connectedDevice == null) {
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        developer.log('❌ BLEManager: Scan cycle error: $e');
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    developer.log('BLEManager: Periodic scanning stopped.');
  }

  Future<bool> _checkBluetoothState() async {
    // ... (ez a metódus maradhat a régiben, már elég robusztus)
    int retryCount = 0;
    const maxRetries = 10;
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;

    while (state == BluetoothAdapterState.unknown && retryCount < maxRetries) {
      developer.log(
          'BLEManager: Bluetooth state unknown, retrying... (${retryCount +
              1}/$maxRetries)');
      await Future.delayed(const Duration(seconds: 3));
      state = await FlutterBluePlus.adapterState.first;
      retryCount++;
    }

    if (state != BluetoothAdapterState.on) {
      developer.log('BLEManager: Bluetooth not available: $state');
      return false;
    }
    developer.log('BLEManager: Bluetooth is ON');
    return true;
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    developer.log(
        '🔗 BLEManager: Attempting to connect to ${device.platformName}');

    // A listen subscription-t egy változóba mentjük, hogy később lemondhassuk
    StreamSubscription<BluetoothConnectionState>? connectionSubscription;

    connectionSubscription =
        device.connectionState.listen((BluetoothConnectionState state) async {
          developer.log(
              '🔗 BLEManager: Connection state changed: $state for ${device
                  .remoteId}');
          if (state == BluetoothConnectionState.disconnected) {
            await connectionSubscription?.cancel();
            _handleDisconnection();
          } else if (state == BluetoothConnectionState.connected) {
            developer.log('✅ BLEManager: Successfully connected to device');
            _isReconnecting = false;
            _reconnectAttempts = 0;
            _reconnectTimer?.cancel();
          }
        });

    try {
      _connectedDevice = device;
      await device.connect(
          autoConnect: false, timeout: const Duration(seconds: 20)); // A 'connect' metódus Duration-t vár, ez jó!
      developer.log('✅ BLEManager: Connected to: ${device.platformName}');

      // JAVÍTÁS: A discoverServices 'int' másodpercet vár, nem Duration-t.
      List<BluetoothService> services = await device.discoverServices(
          timeout: 15 // <-- Így már helyes!
      );
      developer.log('✅ BLEManager: Discovered ${services.length} services');

      for (BluetoothService service in services) {
        await _discoverCharacteristics(service);
      }
    } catch (e) {
      developer.log('❌ BLEManager: Connection error: $e');
      await connectionSubscription.cancel();
      _handleDisconnection();
    }
  }

  Future<void> _discoverCharacteristics(BluetoothService service) async {
    // ... (ez a metódus változatlan maradhat)
    for (BluetoothCharacteristic characteristic in service.characteristics) {
      if (characteristic.properties.notify) {
        await _setupCharacteristicNotifications(characteristic);
      }
    }
  }

  Future<void> _setupCharacteristicNotifications(
      BluetoothCharacteristic characteristic) async {
    // ... (ez a metódus változatlan maradhat)
    await characteristic.setNotifyValue(true);
    characteristic.value.listen((value) {
      if (value.isNotEmpty) {
        try {
          final dataString = String.fromCharCodes(value).trim();
          if (dataString.isNotEmpty && dataString.contains('=')) {
            final deviceName = _connectedDevice?.platformName ?? 'Unknown';
            final taggedData = '$deviceName: $dataString';
            developer.log('BLE Raw Data: $taggedData');
            _dataController.add(taggedData);
          }
        } catch (e) {
          developer.log('BLE Parse error: $e');
        }
      }
    });
  }

  // ================================================================
  // MÓDOSÍTOTT DISCONNECT KEZELÉS
  // ================================================================

  void _handleDisconnection() {
    if (_isReconnecting) return; // Már folyamatban van az újracsatlakozás

    developer.log(
        'BLEManager: Device disconnected - starting reconnection process');
    _disconnectController.add(null);
    _dataController.add('');
    _connectedDevice = null;
    _isPeriodicScanningActive = true;

    _startReconnectionProcess();
  }

  void _startReconnectionProcess() {
    _isReconnecting = true;
    _reconnectAttempts = 0;
    developer.log('🔄 BLEManager: Starting automated reconnection process');

    _reconnectTimer?.cancel(); // Biztonsági leállítás
    _reconnectTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
          if (!_isReconnecting || _reconnectAttempts >= maxReconnectAttempts) {
            developer.log(
                '🔄 BLEManager: Stopping reconnection attempts after $maxReconnectAttempts tries.');
            timer.cancel();
            _isReconnecting = false;
            return;
          }

          _reconnectAttempts++;
          developer.log(
              '🔄 BLEManager: Reconnection attempt $_reconnectAttempts/$maxReconnectAttempts');

          // Újraindítjuk a teljes keresési folyamatot
          await _periodicScan();

          // Ha a periodicScan sikeresen csatlakozott, állítsuk le az újracsatlakozást
          if (_connectedDevice != null) {
            developer.log('✅ BLEManager: Reconnection successful!');
            timer.cancel();
            _isReconnecting = false;
            _reconnectAttempts = 0;
          }
        });
  }
}