import 'package:flutter_test/flutter_test.dart';
import 'package:modbus_ble/modbus_ble.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('crc16Modbus matches a known Renogy realtime read frame', () {
    // ModbusRtu(unitId: 0xFF).readHolding(0x0100, 0x23) == FF 03 01 00 00 23 <crc>
    final f = const ModbusRtu(unitId: 0xFF).readHolding(0x0100, 0x23);
    expect(_hex(f).startsWith('ff0301000023'), isTrue);
    expect(f.length, 8);
    expect(hasValidModbusCrc(f), isTrue);
  });

  test('ModbusAssembler reassembles a 35-register reply split across 20-byte BLE chunks', () {
    final body = [0xFF, 0x03, 70, for (var i = 0; i < 70; i++) i]; // 70 data bytes
    final frame = withModbusCrc(body); // 75 bytes total
    final asm = ModbusAssembler(unitId: 0xFF);
    final out = <ModbusReply>[];
    for (var i = 0; i < frame.length; i += 20) {
      out.addAll(asm.add(frame.sublist(i, i + 20 > frame.length ? frame.length : i + 20)));
    }
    expect(out.length, 1);
    expect(out.first.registers.length, 35);
  });

  test('normalizeUuid expands a 16-bit uuid', () {
    expect(normalizeUuid('ff00'), '0000ff00-0000-1000-8000-00805f9b34fb');
  });
}
