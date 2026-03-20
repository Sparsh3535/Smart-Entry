import 'package:flutter/foundation.dart';
import 'data_utils.dart';

/// Manages day scholar attendance data
class DayScholarManager {
  final List<Map<String, dynamic>> _dayRows = [];
  final ValueNotifier<List<Map<String, dynamic>>> notifier = ValueNotifier(
    const [],
  );

  Function(String)? logCallback;

  List<Map<String, dynamic>> get rows => _dayRows;

  /// Insert or update day-scholar rows:
  /// - first scan for a person -> set 'intime'
  /// - next scan for same person -> set 'outtime'
  /// - if both already present, start a new session (new row with intime)
  void addOrUpdateRow(Map<String, dynamic> fields) {
    _log('[DAY SCHOLAR MANAGER] addOrUpdateRow() called');
    _log('[DAY SCHOLAR MANAGER] Received fields: $fields');

    final String? name = fields['name'] as String?;
    final String? id = fields['id'] as String?;
    final String? phone = fields['phone'] as String?;

    _log('[DAY SCHOLAR MANAGER] name=$name, id=$id, phone=$phone');
    _log('[DAY SCHOLAR MANAGER] Current total rows: ${_dayRows.length}');

    final existingIndex = findExistingRowIndex(_dayRows, id, phone, name);
    _log('[DAY SCHOLAR MANAGER] Found existing row at index: $existingIndex');

    if (existingIndex >= 0) {
      final r = _dayRows[existingIndex];
      final prevIn = (r['intime'] as String?) ?? '';
      final prevOut = (r['outtime'] as String?) ?? '';
      final now = shortDateTime(DateTime.now());

      if (prevIn.trim().isEmpty) {
        // first event -> set intime
        r['intime'] = now;
        _dayRows[existingIndex] = Map<String, dynamic>.from(r);
        logCallback?.call(
          'DayScholar: set intime to $now for id=${id ?? phone ?? name}',
        );
      } else if (prevOut.trim().isEmpty) {
        // intime exists and outtime empty -> set outtime
        r['outtime'] = now;
        _dayRows[existingIndex] = Map<String, dynamic>.from(r);
        logCallback?.call(
          'DayScholar: set outtime to $now for id=${id ?? phone ?? name}',
        );
      } else {
        // both intime+outtime present -> start a new session with new intime
        final newRow = Map<String, dynamic>.from(r);
        newRow['intime'] = now;
        newRow['outtime'] = null;
        newRow['security'] = null;
        _dayRows.add(newRow);
        logCallback?.call(
          'DayScholar: started new session (intime=$now) for id=${id ?? phone ?? name}',
        );
      }
      _log('[DAY SCHOLAR MANAGER] Updates done, setting notifier...');
      notifier.value = List<Map<String, dynamic>>.from(_dayRows);
      _log(
        '[DAY SCHOLAR MANAGER] ✓ Notifier updated with ${notifier.value.length} rows',
      );
      _log('[DAY SCHOLAR MANAGER] Notifier value: ${notifier.value}');
      return;
    }

    // not found -> add with intime set (preserve all incoming fields)
    final normalized = Map<String, dynamic>.from(fields);
    normalized['intime'] = shortDateTime(DateTime.now());
    normalized['outtime'] = null;
    normalized['security'] = null;
    _log('[DAY SCHOLAR MANAGER] Creating new row: $normalized');
    _dayRows.add(normalized);
    _log(
      '[DAY SCHOLAR MANAGER] ✓ Added new entry. Total rows now: ${_dayRows.length}',
    );
    logCallback?.call(
      'DayScholar: added new entry for id=${id ?? phone ?? name}',
    );
    _log('[DAY SCHOLAR MANAGER] Setting notifier with new data...');
    notifier.value = List<Map<String, dynamic>>.from(_dayRows);
    _log(
      '[DAY SCHOLAR MANAGER] ✓ Notifier updated with ${notifier.value.length} rows',
    );
    _log('[DAY SCHOLAR MANAGER] Notifier value: ${notifier.value}');
  }

  /// Helper method for logging
  void _log(String message) {
    logCallback?.call(message);
  }

  void clear() {
    _dayRows.clear();
    notifier.value = [];
  }
}
