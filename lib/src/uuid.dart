/// Expand 16-bit UUIDs ("ff00") to 128-bit and lowercase.
String normalizeUuid(String uuid) {
  final u = uuid.toLowerCase();
  return u.length == 4 ? '0000$u-0000-1000-8000-00805f9b34fb' : u;
}
