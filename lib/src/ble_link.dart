// Shared BLE plumbing for drivers: find the characteristics, subscribe, write in
// chunks, and run request/response exchanges one at a time.

import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'uuid.dart';

class BleLink {
  final BleDevice device;
  final String serviceUuid;
  final String notifyUuid;
  final String writeUuid;

  /// Service holding the write characteristic, when it differs from the notify
  /// service (e.g. Renogy writes on FFD0 but notifies on FFF0).
  final String writeServiceUuid;

  /// Largest write per packet; 20 is safe before MTU negotiation.
  final int chunkSize;
  final bool writeWithResponse;

  BleLink(
    this.device, {
    required String service,
    required String notify,
    required String write,
    String? writeService,
    this.chunkSize = 20,
    this.writeWithResponse = false,
  })  : serviceUuid = normalizeUuid(service),
        notifyUuid = normalizeUuid(notify),
        writeUuid = normalizeUuid(write),
        writeServiceUuid = normalizeUuid(writeService ?? service);

  BleCharacteristic? _tx;
  final List<StreamSubscription<dynamic>> _subs = [];
  final _incoming = StreamController<Uint8List>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  Future<void> _queue = Future.value();

  /// Raw notification chunks.
  Stream<Uint8List> get incoming => _incoming.stream;
  Stream<bool> get connection => _connected.stream;

  Future<void> connect() async {
    _subs.add(device.connectionStream.listen(_connected.add));
    await device.connect();
    final services = await device.discoverServices();
    final svc = services.firstWhere((s) => normalizeUuid(s.uuid) == serviceUuid);
    final writeSvc = writeServiceUuid == serviceUuid
        ? svc
        : services.firstWhere((s) => normalizeUuid(s.uuid) == writeServiceUuid);
    final rx = svc.characteristics.firstWhere((c) => normalizeUuid(c.uuid) == notifyUuid);
    _tx = writeSvc.characteristics.firstWhere((c) => normalizeUuid(c.uuid) == writeUuid);
    _subs.add(rx.onValueReceived.listen((v) => _incoming.add(Uint8List.fromList(v))));
    await rx.notifications.subscribe();
  }

  Future<void> write(List<int> bytes) async {
    final tx = _tx;
    if (tx == null) throw StateError('Not connected');
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = i + chunkSize < bytes.length ? i + chunkSize : bytes.length;
      await tx.write(bytes.sublist(i, end), withResponse: writeWithResponse);
    }
  }

  /// Run [exchange] exclusively: no other exchange interleaves on the link.
  Future<T> exclusive<T>(Future<T> Function() exchange) {
    final result = _queue.then((_) => exchange());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> disconnect() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _tx = null;
    await device.disconnect();
  }
}
