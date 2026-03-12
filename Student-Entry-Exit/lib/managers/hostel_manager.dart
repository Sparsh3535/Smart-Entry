import 'package:flutter/foundation.dart';
import 'data_utils.dart';

/// Manages hostel entry/exit data
class HostelManager {
  final List<Map<String, dynamic>> _hostelRows = [];
  final ValueNotifier<List<Map<String, dynamic>>> notifier = ValueNotifier(
    const [],
  );

  Function(String)? logCallback;

  List<Map<String, dynamic>> get rows => _hostelRows;

  /// Insert or update hostel rows:
  /// - first scan should fill OUT time
  /// - second scan should fill IN time
  /// - if both present, start a new session (again OUT first)
  void addOrUpdateRow(Map<String, dynamic> fields) {
    final name = fields['name'] as String?;
    final id = fields['id'] as String?;
    final phone = fields['phone'] as String?;

    final existingIndex = findExistingRowIndex(_hostelRows, id, phone, name);

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
        final newRow = <String, dynamic>{
          'name': r['name'],
          'id': r['id'],
          'phone': r['phone'],
          'location': fields['location'] ?? r['location'],
          'intime': null,
          'outtime': now,
          'security': null,
        };
        _hostelRows.add(newRow);
        logCallback?.call(
          'Hostel: started new session (outtime=$now) for id=${id ?? phone ?? name}',
        );
      }
      notifier.value = List<Map<String, dynamic>>.from(_hostelRows);
      return;
    }

    // not found -> add with outtime set (first scan)
    final normalized = <String, dynamic>{
      'name': name,
      'id': id,
      'phone': phone,
      'location': fields['location'],
      'intime': null,
      'outtime': shortDateTime(DateTime.now()),
      'security': null,
    };
    _hostelRows.add(normalized);
    logCallback?.call('Hostel: added new entry for id=${id ?? phone ?? name}');
    notifier.value = List<Map<String, dynamic>>.from(_hostelRows);
  }

  void clear() {
    _hostelRows.clear();
    notifier.value = [];
  }
}
