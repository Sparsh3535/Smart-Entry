import 'package:flutter/foundation.dart';
import 'data_utils.dart';
import 'local_storage_service.dart';

/// Manages hostel entry/exit data
class HostelManager {
  final List<Map<String, dynamic>> _hostelRows = [];
  final ValueNotifier<List<Map<String, dynamic>>> notifier = ValueNotifier(
    const [],
  );

  Function(String)? logCallback;

  List<Map<String, dynamic>> get rows => _hostelRows;

  HostelManager() {
    debugPrint('[HOSTEL MANAGER INIT] Manager created');
    debugPrint('[HOSTEL MANAGER INIT] notifier value: ${notifier.value}');
  }

  /// Insert or update hostel rows:
  /// - first scan should fill OUT time
  /// - second scan should fill IN time
  /// - if both present, start a new session (again OUT first)
  void addOrUpdateRow(Map<String, dynamic> fields) {
    _log('[HOSTEL MANAGER] addOrUpdateRow() called');
    _log('[HOSTEL MANAGER] Received fields:');
    _log('[HOSTEL MANAGER] $fields');

    final name = fields['name'] as String?;
    final id = fields['id'] as String?;
    final phone = fields['phone'] as String?;

    _log('[HOSTEL MANAGER] name=$name, id=$id, phone=$phone');
    _log('[HOSTEL MANAGER] Current total rows: ${_hostelRows.length}');

    final existingIndex = findExistingRowIndex(_hostelRows, id, phone, name);
    _log('[HOSTEL MANAGER] Found existing row at index: $existingIndex');

    if (existingIndex >= 0) {
      final r = _hostelRows[existingIndex];
      final prevIn = r['intime'] as String?;
      final prevOut = r['outtime'] as String?;
      final now = shortDateTime(DateTime.now());

      if (prevOut == null || prevOut.toString().trim().isEmpty) {
        // first relevant scan -> set outtime; update location if provided
        r['outtime'] = now;
        final loc = fields['location'];
        if (loc != null && loc.toString().trim().isNotEmpty) {
          r['location'] = loc;
        }
        _hostelRows[existingIndex] = Map<String, dynamic>.from(r);
        logCallback?.call(
          'Hostel: set outtime to $now for id=${id ?? phone ?? name}',
        );
      } else if (prevIn == null || prevIn.toString().trim().isEmpty) {
        // outtime exists but intime empty -> set intime (return/enter); update location
        r['intime'] = now;
        final loc = fields['location'];
        if (loc != null && loc.toString().trim().isNotEmpty) {
          r['location'] = loc;
        }
        _hostelRows[existingIndex] = Map<String, dynamic>.from(r);
        logCallback?.call(
          'Hostel: set intime to $now for id=${id ?? phone ?? name}',
        );
      } else {
        // both intime + outtime present -> start a new session with OUT filled first
        final newRow = Map<String, dynamic>.from(r);
        newRow['location'] = fields['location'] ?? r['location'];
        newRow['intime'] = null;
        newRow['outtime'] = now;
        newRow['security'] = null;
        _hostelRows.add(newRow);
        logCallback?.call(
          'Hostel: started new session (outtime=$now) for id=${id ?? phone ?? name}',
        );
      }
      _log('[HOSTEL MANAGER] Updates done, setting notifier...');
      debugPrint(
        '[HOSTEL MANAGER DEBUG] About to set notifier.value for existing row',
      );
      notifier.value = List<Map<String, dynamic>>.from(_hostelRows);
      _save();
      debugPrint(
        '[HOSTEL MANAGER DEBUG] ✓ Notifier.value set to: ${notifier.value}',
      );
      _log(
        '[HOSTEL MANAGER] ✓ Notifier updated with ${notifier.value.length} rows',
      );
      _log('[HOSTEL MANAGER] Notifier value: ${notifier.value}');
      return;
    }

    // not found -> add with outtime set (first scan, preserve all incoming fields)
    final normalized = Map<String, dynamic>.from(fields);
    normalized['intime'] = null;
    normalized['outtime'] = shortDateTime(DateTime.now());
    normalized['security'] = null;
    _log('[HOSTEL MANAGER] Creating new row: $normalized');
    _hostelRows.add(normalized);
    debugPrint(
      '[HOSTEL MANAGER DEBUG] Added to _hostelRows, count: ${_hostelRows.length}',
    );
    _log(
      '[HOSTEL MANAGER] ✓ Added new entry. Total rows now: ${_hostelRows.length}',
    );
    logCallback?.call('Hostel: added new entry for id=${id ?? phone ?? name}');
    _log('[HOSTEL MANAGER] Setting notifier with new data...');
    debugPrint('[HOSTEL MANAGER DEBUG] About to set notifier.value');
    notifier.value = List<Map<String, dynamic>>.from(_hostelRows);
    _save();
    debugPrint(
      '[HOSTEL MANAGER DEBUG] ✓ Notifier.value set to: ${notifier.value}',
    );
    _log(
      '[HOSTEL MANAGER] ✓ Notifier updated with ${notifier.value.length} rows',
    );
    _log('[HOSTEL MANAGER] Notifier value: ${notifier.value}');
  }

  /// Helper method for logging
  void _log(String message) {
    logCallback?.call(message);
  }

  /// Save current rows to local storage
  void _save() {
    LocalStorageService().save('hostel', _hostelRows);
  }

  /// Load previously saved rows from local storage (daily reset applied)
  Future<void> loadFromStorage() async {
    final saved = await LocalStorageService().load('hostel');
    if (saved.isNotEmpty) {
      _hostelRows.clear();
      _hostelRows.addAll(saved);
      notifier.value = List<Map<String, dynamic>>.from(_hostelRows);
      _log('[HOSTEL MANAGER] Loaded ${saved.length} rows from storage');
    }
  }

  void clear() {
    _hostelRows.clear();
    notifier.value = [];
    LocalStorageService().delete('hostel');
  }
}
