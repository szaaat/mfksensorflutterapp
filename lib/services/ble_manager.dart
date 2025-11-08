import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:developer' as developer;

class BLEManager {
  static final BLEManager _instance = BLEManager._internal();
  factory BLEManager() => _instance;

  BLEManager._internal() {
    FlutterBluePlus.scanResults.listen((results) {
      if (_isPeriodicScanningActive && _connectedDevice == null) {
        for (ScanResult result in results) {
          _handleDiscoveredDevice(result);
        }
      }
    });

    // ⭐️ ELTÁVOLÍTVA: FlutterBluePlus.connectionState - nem létezik
    // Ehelyett az egyes eszközök connectionState streamjét használjuk
  }

  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;

  final StreamController<String> _dataController = StreamController<String>.broadcast();
  final StreamController<void> _disconnectController = StreamController<void>.broadcast();

  Stream<String> get onDataReceived => _dataController.stream;
  Stream<void> get onDisconnected => _disconnectController.stream;

  final Guid sen66ServiceUUID = Guid("12345678-1234-1234-1234-123456789abc");
  final Guid sen66CharacteristicUUID = Guid("87654321-4321-4321-4321-cba987654321");
  final Guid sen55ServiceUUID = Guid("0000181a-0000-1000-8000-00805f9b34fb");

  bool _isPeriodicScanningActive = false;

  Future<void> startScanning() async {
    developer.log('BLEManager: startScanning called');

    if (!await _checkBluetoothState()) return;

    _isPeriodicScanningActive = true;
    _periodicScan();
  }

  Future<void> stopScanning() async {
    _isPeriodicScanningActive = false;
    await FlutterBluePlus.stopScan();

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _connectedDevice = null;
    developer.log('BLEManager: Scanning stopped completely');
  }

  void dispose() {
    _dataController.close();
    _disconnectController.close();
  }

  Future<void> _periodicScan() async {
    while (_isPeriodicScanningActive && _connectedDevice == null) {
      developer.log('BLEManager: Starting a new scan cycle...');

      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 6),
          withServices: [sen55ServiceUUID, sen66ServiceUUID],
        );

        await Future.delayed(const Duration(seconds: 6));
        await FlutterBluePlus.stopScan();

      } catch (e) {
        developer.log('BLEManager: Scan error: $e');
      }

      if (_isPeriodicScanningActive && _connectedDevice == null) {
        developer.log('BLEManager: Scan finished, waiting before next cycle...');
        await Future.delayed(const Duration(seconds: 5));
      }
    }
    developer.log('BLEManager: Periodic scanning stopped.');
  }

  Future<bool> _checkBluetoothState() async {
    int retryCount = 0;
    const maxRetries = 5;
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;

    while (state == BluetoothAdapterState.unknown && retryCount < maxRetries) {
      developer.log('BLEManager: Bluetooth state unknown, retrying... (${retryCount + 1}/$maxRetries)');
      await Future.delayed(const Duration(seconds: 2));
      state = await FlutterBluePlus.adapterState.first;
      retryCount++;
    }

    if (state != BluetoothAdapterState.on) {
      developer.log('BLEManager: Bluetooth not available: $state');
      Future.delayed(const Duration(seconds: 10), startScanning);
      return false;
    }

    developer.log('BLEManager: Bluetooth is ON');
    return true;
  }

  void _handleDiscoveredDevice(ScanResult result) {
    if (_isConnecting || _connectedDevice != null) return;

    final device = result.device;
    final name = device.platformName.isEmpty ? 'N/A' : device.platformName;

    if (name.contains('SEN55') || name.contains('SEN66')) {
      developer.log('🎯 BLEManager: Target device found: $name');
      _isPeriodicScanningActive = false;
      FlutterBluePlus.stopScan();
      _connectToDevice(device);
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting) return;

    _isConnecting = true;

    try {
      // Először szakítsuk meg a régi kapcsolatot, ha van
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      _connectedDevice = device;

      developer.log('🔗 BLEManager: Attempting to connect to: ${device.platformName}');

      // ⭐️ Rövid timeout és autoConnect=true a megbízhatóbb kapcsolódáshoz
      await device.connect(
          autoConnect: true,
          timeout: const Duration(seconds: 8)
      );

      developer.log('✅ BLEManager: Successfully connected to: ${device.platformName}');

      // Szolgáltatások felfedezése
      List<BluetoothService> services = await device.discoverServices();
      developer.log('🔍 BLEManager: Discovered ${services.length} services');

      bool foundCharacteristics = false;
      for (BluetoothService service in services) {
        await _discoverCharacteristics(service);
        foundCharacteristics = true;
      }

      if (!foundCharacteristics) {
        developer.log('⚠️ BLEManager: No characteristics found, disconnecting...');
        await device.disconnect();
        throw Exception('No characteristics found');
      }

      // ⭐️ ERŐSÍTETT kapcsolat állapot figyelése - CSAK az eszköz szintjén
      device.connectionState.listen((BluetoothConnectionState state) async {
        developer.log('🔗 BLEManager: Connection state changed to: $state for ${device.platformName}');

        if (state == BluetoothConnectionState.disconnected) {
          developer.log('🔌 BLEManager: Device disconnected, handling disconnection...');
          await Future.delayed(const Duration(milliseconds: 100));
          _handleDisconnection();
        }
      });

      _isConnecting = false;

    } catch (e) {
      developer.log('❌ BLEManager: Connection error: $e');
      _isConnecting = false;
      _handleDisconnection();
    }
  }

  Future<void> _discoverCharacteristics(BluetoothService service) async {
    for (BluetoothCharacteristic characteristic in service.characteristics) {
      if (characteristic.properties.notify || characteristic.properties.read) {
        developer.log('📡 BLEManager: Setting up notifications for: ${characteristic.uuid}');
        await _setupNotifications(characteristic);
      }
    }
  }

  Future<void> _setupNotifications(BluetoothCharacteristic characteristic) async {
    try {
      await characteristic.setNotifyValue(true);
      characteristic.value.listen((value) {
        if (value.isNotEmpty) {
          try {
            final dataString = String.fromCharCodes(value).trim();
            if (dataString.isNotEmpty && dataString.contains('=')) {
              final deviceName = _connectedDevice?.platformName ?? 'Unknown';
              final taggedData = '$deviceName: $dataString';
              developer.log('📱 BLE Raw Data: $taggedData');
              _dataController.add(taggedData);
            }
          } catch (e) {
            developer.log('❌ BLE Parse error: $e');
          }
        }
      });
      developer.log('✅ BLEManager: Notifications set up for ${characteristic.uuid}');
    } catch (e) {
      developer.log('❌ BLEManager: Error setting up notifications: $e');
    }
  }

  void _handleDisconnection() async {
    if (!_isPeriodicScanningActive) return;

    developer.log('🔄 BLEManager: Starting disconnection handling...');

    // Küldjünk üres adatot a felhasználói felület számára
    _dataController.add('');
    _disconnectController.add(null);

    // Eszköz leválasztása, ha még nem történt meg
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        developer.log('✅ BLEManager: Device disconnected successfully');
      } catch (e) {
        developer.log('⚠️ BLEManager: Error during disconnection: $e');
      }
      _connectedDevice = null;
    }

    _isConnecting = false;

    // ⭐️ RÖVID VÁRAKOZÁS, MAJD AZONNALI ÚJRAINDULÁS
    await Future.delayed(const Duration(seconds: 2));

    if (_isPeriodicScanningActive) {
      developer.log('🔄 BLEManager: Restarting scan after disconnection...');
      startScanning();
    }
  }

  // ⭐️ MANUÁLIS ÚJRAKAPCSOLÓDÁS
  Future<void> reconnect() async {
    developer.log('🔄 BLEManager: Manual reconnect requested');
    _handleDisconnection();
  }
}