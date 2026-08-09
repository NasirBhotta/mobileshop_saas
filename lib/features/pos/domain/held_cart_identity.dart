final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Returns the UUID used for a held cart in the remote database.
///
/// Older app versions used millisecond timestamps as IDs. Mapping those IDs
/// deterministically ensures an already-queued save and its matching delete
/// keep referring to the same remote row, including after an app restart.
String heldCartRemoteId(String id) {
  final normalized = id.trim();
  if (_uuidPattern.hasMatch(normalized)) return normalized;

  final legacyTimestamp = BigInt.tryParse(normalized);
  if (legacyTimestamp == null || legacyTimestamp.isNegative) {
    throw FormatException('Held cart ID is neither a UUID nor a legacy ID', id);
  }

  final lower48Bits = legacyTimestamp & ((BigInt.one << 48) - BigInt.one);
  final suffix = lower48Bits.toRadixString(16).padLeft(12, '0');
  return '00000000-0000-4000-8000-$suffix';
}
