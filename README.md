# modbus_ble

Transport-only building blocks for talking **Modbus RTU over Bluetooth LE**, shared
by Flutter drivers that tunnel Modbus through a BLE characteristic pair.

This package carries no device or domain model — just the plumbing:

- **`BleLink`** — connect, discover, subscribe to a notify characteristic, write in
  MTU-safe chunks, and run request/response exchanges one at a time
  (`exclusive`). Supports a split transport where writes and notifications live on
  different services (`writeService`), e.g. Renogy's FFD0-write / FFF0-notify.
- **`ModbusRtu`** — request frame builders (read holding/input, write single/multiple)
  for one unit (slave) id.
- **`ModbusAssembler`** / **`ModbusReply`** — reassemble notification chunks into
  complete, CRC-checked replies, resynchronising on CRC failure.
- **`crc16Modbus`**, **`withModbusCrc`**, **`hasValidModbusCrc`** — CRC-16/MODBUS.
- **`normalizeUuid`** — expand 16-bit UUIDs to 128-bit, lowercased.

Used by `bms_core` (battery drivers) and `renogy_mppt` (charge-controller driver).

## Usage

```dart
import 'package:modbus_ble/modbus_ble.dart';

final link = BleLink(device,
    service: '0000fff0-0000-1000-8000-00805f9b34fb',   // notify
    notify: '0000fff1-0000-1000-8000-00805f9b34fb',
    writeService: '0000ffd0-0000-1000-8000-00805f9b34fb', // write (if split)
    write: '0000ffd1-0000-1000-8000-00805f9b34fb',
    writeWithResponse: false);
final asm = ModbusAssembler(unitId: 0xFF);
link.incoming.listen((chunk) => asm.add(chunk).forEach(handleReply));
await link.connect();
await link.write(const ModbusRtu(unitId: 0xFF).readHolding(0x0100, 0x23));
```
