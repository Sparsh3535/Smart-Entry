import 'package:flutter/foundation.dart';
import 'data_utils.dart';
import 'local_storage_service.dart';

/// Manages leave application data
class LeaveApplicationsManager {
  final List<Map<String, dynamic>> _leaveApps = [];
  final ValueNotifier<List<Map<String, dynamic>>> notifier = ValueNotifier(
    const [],
  );

  Function(String)? logCallback;

  /// Called when an entry is complete (both leaving and returning filled)
  /// with the _docId so Firebase document can be deleted
  Function(String docId)? onEntryComplete;

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
          'roomNumber': low['roomnumber'] ?? low['room_number'] ?? '',
          'leaving': low['leaving'] ?? '',
          'returning': low['returning'] ?? '',
          'duration': low['duration'] ?? '',
          'address': low['address'] ?? low['addressduringleave'] ?? '',
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
        'roomNumber': map['roomnumber'] ?? map['room_number'] ?? '',
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

  /// Insert or update leave rows (same pattern as hostel/day scholar):
  /// - first scan → add new row with 'leaving' set, 'returning' empty
  /// - second scan → fill 'returning' with current date/time
  /// - if both filled → start new row
  void addOrUpdateRow(Map<String, dynamic> fields) {
    _log('[LEAVE MANAGER] addOrUpdateRow() called');
    _log('[LEAVE MANAGER] Received fields: $fields');

    final String? name = fields['name'] as String?;
    final String? id = fields['id'] as String?;
    final String? phone = fields['phone'] as String?;

    _log('[LEAVE MANAGER] name=$name, id=$id, phone=$phone');
    _log('[LEAVE MANAGER] Current total rows: ${_leaveApps.length}');

    final existingIndex = findExistingRowIndex(_leaveApps, id, phone, name);
    _log('[LEAVE MANAGER] Found existing row at index: $existingIndex');

    if (existingIndex >= 0) {
      final r = _leaveApps[existingIndex];
      final prevReturning = (r['returning'] as String?) ?? '';
      final now = shortDateTime(DateTime.now());

      // Update _docId from incoming data (may be missing in cached rows)
      if (fields['_docId'] != null) {
        r['_docId'] = fields['_docId'];
        debugPrint('[LEAVE MANAGER] Updated _docId to: ${fields['_docId']}');
      } else {
        debugPrint('[LEAVE MANAGER] WARNING: incoming fields has no _docId!');
      }

      // Update leaving from incoming data if it has a newer/more complete value
      final incomingLeaving = fields['leaving']?.toString() ?? '';
      if (incomingLeaving.isNotEmpty) {
        r['leaving'] = incomingLeaving;
      }

      if (prevReturning.trim().isEmpty) {
        // returning empty → fill it
        r['returning'] = now;
        _leaveApps[existingIndex] = Map<String, dynamic>.from(r);
        logCallback?.call(
          'Leave: set returning to $now for id=${id ?? phone ?? name}',
        );
        // Both filled → trigger Firebase delete
        final docId = r['_docId']?.toString();
        debugPrint('[LEAVE MANAGER] Entry complete. _docId=$docId, onEntryComplete=${onEntryComplete != null ? "SET" : "NULL"}');
        if (docId != null && docId.isNotEmpty) {
          onEntryComplete?.call(docId);
          debugPrint('[LEAVE MANAGER] ✓ Called onEntryComplete with docId=$docId');
        } else {
          debugPrint('[LEAVE MANAGER] ✗ Cannot delete: _docId is null or empty');
        }
      } else {
        // both filled → start new row
        final newRow = Map<String, dynamic>.from(r);
        newRow['returning'] = null;
        newRow['receivedAt'] = now;
        _leaveApps.add(newRow);
        logCallback?.call(
          'Leave: started new session for id=${id ?? phone ?? name}',
        );
      }
      _log('[LEAVE MANAGER] Updates done, setting notifier...');
      notifier.value = List<Map<String, dynamic>>.from(_leaveApps);
      _save();
      _log('[LEAVE MANAGER] ✓ Notifier updated with ${notifier.value.length} rows');
      return;
    }

    // not found → add with leaving set, returning empty (preserve all fields)
    final normalized = Map<String, dynamic>.from(fields);
    normalized['returning'] = null;
    normalized['receivedAt'] = shortDateTime(DateTime.now());
    _log('[LEAVE MANAGER] Creating new row: $normalized');
    _leaveApps.add(normalized);
    _log('[LEAVE MANAGER] ✓ Added new entry. Total rows now: ${_leaveApps.length}');
    logCallback?.call('Leave: added new entry for id=${id ?? phone ?? name}');
    notifier.value = List<Map<String, dynamic>>.from(_leaveApps);
    _save();
    _log('[LEAVE MANAGER] ✓ Notifier updated with ${notifier.value.length} rows');
  }

  /// Helper method for logging
  void _log(String message) {
    logCallback?.call(message);
  }

  /// Save current rows to local storage
  void _save() {
    LocalStorageService().save('leave', _leaveApps);
  }

  /// Load saved leave rows with selective midnight reset:
  /// - Completed entries (all key fields filled) from previous days are removed
  /// - Incomplete entries (e.g. returning is empty) persist until filled
  Future<void> loadFromStorage() async {
    final saved = await LocalStorageService().loadRaw('leave');
    if (saved.isEmpty) {
      _log('[LEAVE MANAGER] No saved leave data');
      return;
    }

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final filtered = saved.where((row) {
      final leaving = (row['leaving']?.toString() ?? '').trim();
      final returning = (row['returning']?.toString() ?? '').trim();
      final isComplete = leaving.isNotEmpty && returning.isNotEmpty;

      if (!isComplete) {
        // Incomplete entry — keep it regardless of date
        return true;
      }

      // Completed entry — only keep if from today
      final receivedAt = row['receivedAt']?.toString() ?? '';
      if (receivedAt.length >= 10) {
        final dateStr = receivedAt.substring(0, 10); // "yyyy-MM-dd"
        if (dateStr != todayStr) {
          _log('[LEAVE MANAGER] Removing completed entry from $dateStr: ${row['name']}');
          return false; // remove
        }
      }
      return true; // keep
    }).toList();

    _leaveApps.clear();
    _leaveApps.addAll(filtered);
    notifier.value = List<Map<String, dynamic>>.from(_leaveApps);
    _save(); // re-save the filtered list
    _log('[LEAVE MANAGER] Loaded ${filtered.length} rows (removed ${saved.length - filtered.length} completed entries from previous days)');
  }

  void clear() {
    _leaveApps.clear();
    notifier.value = [];
    LocalStorageService().delete('leave');
  }
}
