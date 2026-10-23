/// Transport-only building blocks for Modbus-RTU-over-BLE drivers: BLE link
/// plumbing, Modbus RTU framing and reassembly, and UUID normalization. Carries
/// no device or domain model.
library;

export 'src/ble_link.dart';
export 'src/modbus.dart';
export 'src/uuid.dart';
