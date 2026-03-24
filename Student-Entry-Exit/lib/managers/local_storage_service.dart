import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Singleton service for persisting manager data to local JSON files.
/// Data is saved with today's date and auto-cleared on the next day (midnight reset).
class LocalStorageService {
  static final LocalStorageService _instance = LocalStorageService._();
  factory LocalStorageService() => _instance;
  LocalStorageService._();

  /// Get the data directory (next to the executable)
  Directory get _dataDir {
    final exeDir = File(Platform.resolvedExecutable).parent;
    return Directory('${exeDir.path}${Platform.pathSeparator}data');
  }

  /// Get today's date as yyyy-MM-dd string (day resets at midnight).
  String get _today {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  /// Recursively convert all values to JSON-safe types
  dynamic _sanitize(dynamic value) {
    if (value == null || value is bool || value is num || value is String) {
      return value;
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitize(v)));
    }
    if (value is List) {
      return value.map((v) => _sanitize(v)).toList();
    }
    // Fallback: convert to string (handles Timestamp, etc.)
    return value.toString();
  }

  /// Save rows for a given key (e.g. 'day_scholar', 'hostel', 'leave')
  Future<void> save(String key, List<Map<String, dynamic>> rows) async {
    try {
      final dir = _dataDir;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File('${dir.path}${Platform.pathSeparator}$key.json');
      final payload = {
        'date': _today,
        'rows': _sanitize(rows),
      };
      await file.writeAsString(jsonEncode(payload));
      debugPrint('[LocalStorage] Saved ${rows.length} rows for "$key" (date: $_today)');
    } catch (e) {
      debugPrint('[LocalStorage] Error saving "$key": $e');
    }
  }

  /// Load rows for a given key. Returns empty list if:
  /// - File doesn't exist
  /// - Saved date is not today (daily reset)
  Future<List<Map<String, dynamic>>> load(String key) async {
    try {
      final file = File('${_dataDir.path}${Platform.pathSeparator}$key.json');
      if (!await file.exists()) {
        debugPrint('[LocalStorage] No saved data for "$key"');
        return [];
      }

      final content = await file.readAsString();
      final payload = jsonDecode(content) as Map<String, dynamic>;
      final savedDate = payload['date'] as String?;

      if (savedDate != _today) {
        debugPrint('[LocalStorage] Data for "$key" is from $savedDate (today: $_today) — clearing');
        await file.delete();
        return [];
      }

      final rawRows = payload['rows'] as List<dynamic>;
      final rows = rawRows
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      debugPrint('[LocalStorage] Loaded ${rows.length} rows for "$key" (date: $savedDate)');
      return rows;
    } catch (e) {
      debugPrint('[LocalStorage] Error loading "$key": $e');
      return [];
    }
  }

  /// Load rows WITHOUT date-based clearing (returns all saved rows regardless of date)
  /// Used by leave applications which have custom clearing logic
  Future<List<Map<String, dynamic>>> loadRaw(String key) async {
    try {
      final file = File('${_dataDir.path}${Platform.pathSeparator}$key.json');
      if (!await file.exists()) {
        debugPrint('[LocalStorage] No saved data for "$key"');
        return [];
      }

      final content = await file.readAsString();
      final payload = jsonDecode(content) as Map<String, dynamic>;
      final rawRows = payload['rows'] as List<dynamic>;
      final rows = rawRows
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      debugPrint('[LocalStorage] Loaded ${rows.length} raw rows for "$key" (no date filter)');
      return rows;
    } catch (e) {
      debugPrint('[LocalStorage] Error loading raw "$key": $e');
      return [];
    }
  }

  /// Delete saved data for a given key
  Future<void> delete(String key) async {
    try {
      final file = File('${_dataDir.path}${Platform.pathSeparator}$key.json');
      if (await file.exists()) {
        await file.delete();
        debugPrint('[LocalStorage] Deleted data for "$key"');
      }
    } catch (e) {
      debugPrint('[LocalStorage] Error deleting "$key": $e');
    }
  }
}
