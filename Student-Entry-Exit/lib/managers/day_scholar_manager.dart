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
    final String? name = fields['name'] as String?;
    final String? id = fields['id'] as String?;
    final String? phone = fields['phone'] as String?;

    final existingIndex = findExistingRowIndex(_dayRows, id, phone, name);

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
        final newRow = <String, dynamic>{
          'name': r['name'],
          'id': r['id'],
          'phone': r['phone'],
          'location': r['location'],
          'intime': now,
          'outtime': null,
          'security': null,
        };
        _dayRows.add(newRow);
        logCallback?.call(
          'DayScholar: started new session (intime=$now) for id=${id ?? phone ?? name}',
        );
      }
      notifier.value = List<Map<String, dynamic>>.from(_dayRows);
      return;
    }

    // not found -> add with intime set
    final normalized = <String, dynamic>{
      'name': name,
      'id': id,
      'phone': phone,
      'location': fields['location'],
      'intime': shortDateTime(DateTime.now()),
      'outtime': null,
      'security': null,
    };
    _dayRows.add(normalized);
    logCallback?.call(
      'DayScholar: added new entry for id=${id ?? phone ?? name}',
    );
    notifier.value = List<Map<String, dynamic>>.from(_dayRows);
  }

  void clear() {
    _dayRows.clear();
    notifier.value = [];
  }
}
