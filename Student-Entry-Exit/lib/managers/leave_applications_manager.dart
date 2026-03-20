import 'package:flutter/foundation.dart';
import 'data_utils.dart';

/// Manages leave application data
class LeaveApplicationsManager {
  final List<Map<String, dynamic>> _leaveApps = [];
  final ValueNotifier<List<Map<String, dynamic>>> notifier = ValueNotifier(
    const [],
  );

  Function(String)? logCallback;

  List<Map<String, dynamic>> get rows => _leaveApps;

  /// Try to parse leave application from String or Map. Returns normalized map or null.
  Map<String, dynamic>? parseLeaveApplication(dynamic src) {
    _log('[LEAVE MANAGER] parseLeaveApplication() called with: $src');

    if (src == null) {
      _log('[LEAVE MANAGER] ⚠ Source is null, returning null');
      return null;
    }
    String? s;
    if (src is String) {
      s = src;
    } else if (src is Map) {
      _log('[LEAVE MANAGER] Source is a Map, checking for leave fields...');
      // lowercase keys
      final low = <String, String>{};
      src.forEach(
        (k, v) => low[k.toString().toLowerCase()] = v?.toString() ?? '',
      );
      if ((low['type'] ?? '').toLowerCase().contains('leave') ||
          low.containsKey('leaving') ||
          low.containsKey('returning')) {
        _log('[LEAVE MANAGER] ✓ Found leave data in Map');
        return {
          'type': 'Leave',
          'name': low['name'] ?? '',
          'id': low['roll number'] ?? low['roll'] ?? low['id'] ?? '',
          'phone': low['phone number'] ?? low['phone'] ?? '',
          'leaving': low['leaving'] ?? '',
          'returning': low['returning'] ?? '',
          'duration': low['duration'] ?? '',
          'address': low['address'] ?? '',
          'receivedAt': shortDateTime(DateTime.now()),
        };
      }
      if (src.containsKey('value') && src['value'] is String) {
        s = src['value'] as String;
      }
    }

    if (s == null) {
      _log('[LEAVE MANAGER] ⚠ No string content found, returning null');
      return null;
    }

    final map = <String, String>{};
    for (final line in s.split(RegExp(r'[\r\n]+'))) {
      final m = RegExp(r'^\s*([^:]+)\s*:\s*(.+)$').firstMatch(line);
      if (m != null) map[m.group(1)!.trim().toLowerCase()] = m.group(2)!.trim();
    }
    if (map.isEmpty) {
      _log('[LEAVE MANAGER] ⚠ Map is empty after parsing, returning null');
      return null;
    }

    final type = map['type'] ?? '';
    if (type.toLowerCase().contains('leave') ||
        map.containsKey('leaving') ||
        map.containsKey('returning')) {
      _log('[LEAVE MANAGER] ✓ Found leave data in parsed string');
      return {
        'type': 'Leave',
        'name': map['name'] ?? '',
        'id': map['roll number'] ?? map['roll'] ?? map['id'] ?? '',
        'phone': map['phone number'] ?? map['phone'] ?? '',
        'leaving': map['leaving'] ?? '',
        'returning': map['returning'] ?? '',
        'duration': map['duration'] ?? '',
        'address': map['address'] ?? '',
        'receivedAt': shortDateTime(DateTime.now()),
      };
    }
    _log('[LEAVE MANAGER] ⚠ No leave data found, returning null');
    return null;
  }

  /// Add a new leave application
  void addLeaveApplication(Map<String, dynamic> app) {
    _log('[LEAVE MANAGER] addLeaveApplication() called');
    _log('[LEAVE MANAGER] Adding leave application: $app');
    _leaveApps.add(app);
    _log(
      '[LEAVE MANAGER] ✓ Added application. Total apps now: ${_leaveApps.length}',
    );
    logCallback?.call('Leave: added application for ${app['name']}');
    notifier.value = List<Map<String, dynamic>>.from(_leaveApps);
    _log('[LEAVE MANAGER] ✓ Updated notifier');
  }

  /// Helper method for logging
  void _log(String message) {
    logCallback?.call(message);
  }

  void clear() {
    _leaveApps.clear();
    notifier.value = [];
  }
}
