// Shared utilities for data processing across all managers

String shortDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

String? firstString(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    if (m.containsKey(k) && m[k] != null) {
      final v = m[k];
      return v is String ? v : v.toString();
    }
  }
  return null;
}

// Check if person already exists in target list (by id -> phone -> name)
int findExistingRowIndex(
  List<Map<String, dynamic>> target,
  String? id,
  String? phone,
  String? name,
) {
  for (var i = target.length - 1; i >= 0; i--) {
    final r = target[i];
    final sameById = id != null && r['id'] != null && r['id'].toString() == id;
    final sameByPhone =
        (id == null || !sameById) &&
        phone != null &&
        r['phone'] != null &&
        r['phone'].toString() == phone;
    final sameByName =
        (id == null && phone == null) &&
        name != null &&
        r['name'] != null &&
        r['name'].toString() == name;

    if (sameById || sameByPhone || sameByName) {
      return i;
    }
  }
  return -1;
}

// Parse key:value block (string or Map) into lowercase key -> value map.
Map<String, String> parseKeyValueBlock(dynamic src) {
  final Map<String, String> out = {};
  String? s;
  if (src == null) return out;
  if (src is String) {
    s = src;
  } else if (src is Map) {
    // If the map already contains labelled keys, return them lowercased.
    final hasNonValueKeys = src.keys.any(
      (k) => k.toString().toLowerCase() != 'value',
    );
    if (hasNonValueKeys) {
      src.forEach((k, v) {
        out[k.toString().toLowerCase()] = v?.toString() ?? '';
      });
      return out;
    }
    if (src.containsKey('value') && src['value'] is String) {
      s = src['value'] as String;
    }
  }
  if (s == null) return out;
  for (final line in s.split(RegExp(r'[\r\n]+'))) {
    final m = RegExp(r'^\s*([^:]+)\s*:\s*(.+)$').firstMatch(line);
    if (m != null) {
      out[m.group(1)!.trim().toLowerCase()] = m.group(2)!.trim();
    }
  }
  return out;
}
