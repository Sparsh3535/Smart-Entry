import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Stores the current security guard name locally.
/// Only one name is stored at a time — saving a new name erases the old one.
class SecurityNameService {
  static final SecurityNameService _instance = SecurityNameService._();
  factory SecurityNameService() => _instance;
  SecurityNameService._();

  String _name = '';

  /// Current security guard name
  String get name => _name;

  /// Whether a name has been set
  bool get isSet => _name.isNotEmpty;

  /// Config file path (next to the executable)
  File get _configFile {
    final exeDir = File(Platform.resolvedExecutable).parent;
    return File('${exeDir.path}${Platform.pathSeparator}data${Platform.pathSeparator}security_name.json');
  }

  /// Load the saved name from disk
  Future<void> load() async {
    try {
      final file = _configFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final config = jsonDecode(content) as Map<String, dynamic>;
        _name = (config['securityName'] as String?) ?? '';
        debugPrint('[SecurityNameService] Loaded name: $_name');
      }
    } catch (e) {
      debugPrint('[SecurityNameService] Error loading: $e');
    }
  }

  /// Save a new name, replacing the old one
  Future<void> save(String newName) async {
    _name = newName.trim();
    try {
      final file = _configFile;
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(jsonEncode({'securityName': _name}));
      debugPrint('[SecurityNameService] Saved name: $_name');
    } catch (e) {
      debugPrint('[SecurityNameService] Error saving: $e');
    }
  }

  /// Clear the stored name
  Future<void> clear() async {
    _name = '';
    try {
      final file = _configFile;
      if (await file.exists()) {
        await file.delete();
      }
      debugPrint('[SecurityNameService] Cleared name');
    } catch (e) {
      debugPrint('[SecurityNameService] Error clearing: $e');
    }
  }
}
