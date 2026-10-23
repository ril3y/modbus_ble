// Modbus RTU framing, transport-agnostic. Several drivers (BMS families, Renogy
// charge controllers, ...) tunnel Modbus RTU over a BLE characteristic pair.

import 'dart:typed_data';

const int fnReadHolding = 0x03;
const int fnReadInput = 0x04;
const int fnWriteSingle = 0x06;
const int fnWriteMultiple = 0x10;

/// CRC-16/Modbus: reflected poly 0xA001, init 0xFFFF. Sent low byte first.
int crc16Modbus(List<int> data) {
  var c = 0xFFFF;
  for (final b in data) {
    c ^= b & 0xFF;
    for (var i = 0; i < 8; i++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xA001 : c >> 1;
    }
  }
  return c;
}

Uint8List withModbusCrc(List<int> body) {
  final c = crc16Modbus(body);
  return Uint8List.fromList([...body, c & 0xFF, c >> 8]);
}

bool hasValidModbusCrc(List<int> frame) {
  if (frame.length < 3) return false;
  final c = crc16Modbus(frame.sublist(0, frame.length - 2));
  return frame[frame.length - 2] == (c & 0xFF) && frame[frame.length - 1] == (c >> 8);
}

/// Request builders for one Modbus unit (slave) id.
class ModbusRtu {
  final int unitId;
  const ModbusRtu({this.unitId = 1});

  Uint8List readHolding(int address, int count) =>
      withModbusCrc([unitId, fnReadHolding, address >> 8, address & 0xFF, count >> 8, count & 0xFF]);

  Uint8List readInput(int address, int count) =>
      withModbusCrc([unitId, fnReadInput, address >> 8, address & 0xFF, count >> 8, count & 0xFF]);

  Uint8List writeSingle(int address, int value) =>
      withModbusCrc([unitId, fnWriteSingle, address >> 8, address & 0xFF, (value >> 8) & 0xFF, value & 0xFF]);

  Uint8List writeMultiple(int address, List<int> values) => withModbusCrc([
        unitId, fnWriteMultiple, address >> 8, address & 0xFF, values.length >> 8, values.length & 0xFF,
        values.length * 2,
        for (final v in values) ...[(v >> 8) & 0xFF, v & 0xFF],
      ]);
}

/// A complete, CRC-checked Modbus reply.
class ModbusReply {
  final int unitId;
  final int function;

  /// Payload: register bytes for reads, the echo for writes, or the
  /// exception code for an error reply.
  final Uint8List data;
  final Uint8List frame;

  ModbusReply(this.unitId, this.function, this.data, this.frame);

  bool get isException => function & 0x80 != 0;
  int get exceptionCode => isException ? data[0] : 0;

  /// Big-endian 16-bit registers of a read reply.
  List<int> get registers => [for (var i = 0; i + 1 < data.length; i += 2) (data[i] << 8) | data[i + 1]];
}

/// Reassembles notification chunks into replies for [unitId], resynchronising
/// on CRC failure. Handles reads (0x03/0x04), writes (0x06/0x10) and exceptions.
class ModbusAssembler {
  final int unitId;
  final List<int> _buf = [];

  ModbusAssembler({this.unitId = 1});

  List<ModbusReply> add(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <ModbusReply>[];
    while (true) {
      final start = _buf.indexOf(unitId);
      if (start < 0) {
        _buf.clear();
        break;
      }
      if (start > 0) _buf.removeRange(0, start);
      if (_buf.length < 2) break;
      final fn = _buf[1];
      final int total;
      final int dataStart;
      if (fn == fnReadHolding || fn == fnReadInput) {
        if (_buf.length < 3) break;
        // A 128-register reply has byte count 256, which wraps to 0.
        total = (_buf[2] == 0 ? 256 : _buf[2]) + 5;
        dataStart = 3;
      } else if (fn == fnWriteSingle || fn == fnWriteMultiple) {
        total = 8;
        dataStart = 2;
      } else if (fn & 0x80 != 0) {
        total = 5;
        dataStart = 2;
      } else {
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < total) break;
      final frame = Uint8List.fromList(_buf.sublist(0, total));
      if (hasValidModbusCrc(frame)) {
        out.add(ModbusReply(unitId, fn, Uint8List.fromList(frame.sublist(dataStart, total - 2)), frame));
        _buf.removeRange(0, total);
      } else {
        _buf.removeAt(0);
      }
    }
    return out;
  }

  void clear() => _buf.clear();
}
