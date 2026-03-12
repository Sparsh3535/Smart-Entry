import 'dart:convert';
import '../managers/day_scholar_manager.dart';
import '../managers/hostel_manager.dart';
import '../managers/leave_applications_manager.dart';
import 'data_utils.dart';

/// Handles QR/socket data authentication and routing to appropriate managers
class QRAuthenticator {
  final DayScholarManager dayScholarManager;
  final HostelManager hostelManager;
  final LeaveApplicationsManager leaveManager;

  Function(String)? logCallback;

  QRAuthenticator({
    required this.dayScholarManager,
    required this.hostelManager,
    required this.leaveManager,
  });

  /// Process incoming buffer data (handles JSON and key:value pairs)
  void processBuffer({
    required String Function() bufferHolder,
    required void Function(String) bufferSetter,
    String? clientAddr,
  }) {
    String buf = bufferHolder();
    while (buf.isNotEmpty) {
      final nlIndex = buf.indexOf('\n');
      if (nlIndex >= 0) {
        final line = buf.substring(0, nlIndex).trim();
        if (line.isNotEmpty) processLine(line);
        buf = buf.substring(nlIndex + 1);
        continue;
      }
      final firstNonWs = _firstNonWhitespaceIndex(buf);
      if (firstNonWs < 0) {
        buf = '';
        break;
      }
      final startChar = buf[firstNonWs];
      if (startChar == '{' || startChar == '[') {
        final endIndex = _findJsonEnd(buf, firstNonWs);
        if (endIndex >= 0) {
          final jsonStr = buf.substring(firstNonWs, endIndex + 1);
          processLine(jsonStr);
          buf = buf.substring(endIndex + 1);
          continue;
        }
        break;
      }
      processLine(buf.trim());
      buf = '';
      break;
    }
    bufferSetter(buf);
  }

  /// Process individual line of data (JSON or raw text)
  void processLine(String line) {
    if (line.isEmpty) return;
    _log(
      'Processing line (${line.length} chars): ${line.length > 200 ? '${line.substring(0, 200)}...' : line}',
    );
    try {
      final decoded = jsonDecode(line);
      if (decoded is List) {
        for (final e in decoded) {
          _processData(e);
        }
      } else {
        _processData(decoded);
      }
      _log('Parsed JSON successfully');
    } catch (e) {
      _processData({'raw': line});
      _log('Failed JSON parse — stored raw');
    }
  }

  /// Process and route data to appropriate manager based on type or content
  void _processData(dynamic obj) {
    Map<String, dynamic> raw;
    if (obj is Map<String, dynamic>) {
      raw = Map<String, dynamic>.from(obj);
    } else {
      raw = {'value': obj?.toString()};
    }

    // If value contains key:value block, parse and merge into raw
    final kvFromValue = parseKeyValueBlock(raw['value'] ?? raw);
    if (kvFromValue.isNotEmpty) {
      kvFromValue.forEach((k, v) {
        // prefer existing explicit keys in raw; otherwise inject parsed value
        if (!raw.containsKey(k) ||
            raw[k] == null ||
            raw[k].toString().trim().isEmpty) {
          raw[k] = v;
        }
        // also add a capitalized variants to help older lookups
        final cap = _capitalizedKey(k);
        if (!raw.containsKey(cap) ||
            raw[cap] == null ||
            raw[cap].toString().trim().isEmpty) {
          raw[cap] = v;
        }
      });
    }

    // If this data has a Type and it routes to leave/day/hostel, let routing handle it.
    if (_routeByType(raw)) return;

    // Default: unrouted data
    _log('Unrouted data: ${raw.toString().substring(0, 100)}');
  }

  /// Route incoming raw map/text by its Type key
  /// Returns true if routed (so caller doesn't try again)
  bool _routeByType(Map<String, dynamic> raw) {
    // try direct keys first
    String? type = firstString(raw, ['type', 'Type']);
    final kv = parseKeyValueBlock(raw);
    type ??= kv['type'];
    if (type == null) return false;
    final t = type.toLowerCase();

    // prefer possible value string for leave parsing
    final possibleValue = raw['value'] ?? kv['value'];

    // ===== LEAVE =====
    if (t.contains('leave')) {
      final pl =
          leaveManager.parseLeaveApplication(raw) ??
          leaveManager.parseLeaveApplication(possibleValue);
      if (pl != null) {
        leaveManager.addLeaveApplication(pl);
        _log('Routed to Leave Applications');
        return true;
      }
      return false;
    }

    // ===== HOSTEL =====
    if (t.contains('hostel') || t.contains('hosteller')) {
      final name = firstString(raw, ['name', 'Name']) ?? kv['name'];
      final id =
          firstString(raw, ['id', 'Id', 'roll', 'roll_no', 'rollno']) ??
          kv['roll number'] ??
          kv['roll'];
      final phone =
          firstString(raw, ['phone', 'Phone', 'mobile']) ??
          kv['phone number'] ??
          kv['phone'];
      final location =
          firstString(raw, ['location', 'Location', 'address']) ??
          kv['location'];
      final minimal = <String, dynamic>{
        'name': name,
        'id': id,
        'phone': phone,
        'location': location,
      };
      hostelManager.addOrUpdateRow(minimal);
      _log('Routed to Hostel');
      return true;
    }

    // ===== DAY SCHOLAR =====
    if (t.contains('day') || t.contains('scholar')) {
      final name = firstString(raw, ['name', 'Name']) ?? kv['name'];
      final id =
          firstString(raw, ['id', 'Id', 'roll', 'roll_no', 'rollno']) ??
          kv['roll number'] ??
          kv['roll'];
      final phone =
          firstString(raw, ['phone', 'Phone', 'mobile']) ??
          kv['phone number'] ??
          kv['phone'];
      final location =
          firstString(raw, ['location', 'Location', 'address']) ??
          kv['location'];
      final minimal = <String, dynamic>{
        'name': name,
        'id': id,
        'phone': phone,
        'location': location,
      };
      dayScholarManager.addOrUpdateRow(minimal);
      _log('Routed to Day Scholar');
      return true;
    }

    return false;
  }

  // ===== HELPER METHODS =====

  String _capitalizedKey(String k) {
    if (k.isEmpty) return k;
    final parts = k.split(RegExp(r'\s+'));
    return parts
        .map((p) => p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1)))
        .join(' ');
  }

  int _firstNonWhitespaceIndex(String s) {
    for (var i = 0; i < s.length; i++) {
      if (s[i].trim().isNotEmpty) return i;
    }
    return -1;
  }

  int _findJsonEnd(String s, int start) {
    final openChar = s[start];
    final closeChar = (openChar == '{') ? '}' : ']';
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < s.length; i++) {
      final ch = s[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == '\\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      } else {
        if (ch == '"') {
          inString = true;
          continue;
        }
        if (ch == openChar) {
          depth++;
        } else if (ch == closeChar) {
          depth--;
          if (depth == 0) return i;
        }
      }
    }
    return -1;
  }

  void _log(String s) {
    final line = '[QR] $s';
    logCallback?.call(line);
  }
}
