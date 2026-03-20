import 'package:cloud_firestore/cloud_firestore.dart';

/// Firebase service to fetch student data from Firestore
/// Collections: gate_passes, leave_requests
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  late final FirebaseFirestore _firestore;

  FirebaseService._internal() {
    _firestore = FirebaseFirestore.instance;
  }

  factory FirebaseService() {
    return _instance;
  }

  /// Fetch student data by Firestore document ID (the key received on port 9000)
  /// Checks both gate_passes and leave_requests collections
  /// Retries if critical fields are empty after normalization
  Future<Map<String, dynamic>?> fetchByDocumentId(String docId) async {
    try {
      print('[Firebase Service] Starting fetch for docId: $docId');
      int retryCount = 0;
      const int maxRetries = 2;

      while (retryCount <= maxRetries) {
        if (retryCount > 0) {
          print(
            '[Firebase Service] Retrying fetch (attempt ${retryCount + 1}/$maxRetries) for docId: $docId',
          );
        }

        // Try to fetch from gate_passes collection
        print('[Firebase Service] Querying gate_passes collection...');
        final gatePassDoc = await _firestore
            .collection('gate_passes')
            .doc(docId)
            .get();

        if (gatePassDoc.exists) {
          final gatePassData = gatePassDoc.data() as Map<String, dynamic>;
          print('[Firebase Service] ✓ Found in gate_passes collection');
          print('[Firebase Service] Raw data: $gatePassData');
          final normalized = _normalizeGatePassData(gatePassData);
          print('[Firebase Service] Normalized data: $normalized');

          // Check if critical fields are populated
          if (_isValidNormalizedData(normalized)) {
            print('[Firebase Service] ✓ Normalized data has required fields');
            return normalized;
          } else {
            print(
              '[Firebase Service] ⚠ Critical fields are empty in normalized data',
            );
            if (retryCount < maxRetries) {
              retryCount++;
              await Future.delayed(Duration(milliseconds: 500));
              continue;
            }
            return normalized; // Return even if empty after retries
          }
        }

        print(
          '[Firebase Service] Not found in gate_passes, checking leave_requests...',
        );
        // If not found in gate_passes, try leave_requests
        final leaveDoc = await _firestore
            .collection('leave_requests')
            .doc(docId)
            .get();

        if (leaveDoc.exists) {
          final leaveData = leaveDoc.data() as Map<String, dynamic>;
          print('[Firebase Service] ✓ Found in leave_requests collection');
          print('[Firebase Service] Raw data: $leaveData');
          final normalized = _normalizeLeaveRequestData(leaveData);
          print('[Firebase Service] Normalized data: $normalized');

          // Check if critical fields are populated
          if (_isValidNormalizedData(normalized)) {
            print('[Firebase Service] ✓ Normalized data has required fields');
            return normalized;
          } else {
            print(
              '[Firebase Service] ⚠ Critical fields are empty in normalized data',
            );
            if (retryCount < maxRetries) {
              retryCount++;
              await Future.delayed(Duration(milliseconds: 500));
              continue;
            }
            return normalized; // Return even if empty after retries
          }
        }

        // Document not found, break retry loop
        if (retryCount == 0) {
          print(
            '[Firebase Service] ✗ Document not found in any collection for docId: $docId',
          );
          return null;
        }
        retryCount++;
      }

      return null;
    } catch (e) {
      print('[Firebase Service] ✗ ERROR fetching docId "$docId": $e');
      return null;
    }
  }

  /// Check if normalized data has required fields populated
  bool _isValidNormalizedData(Map<String, dynamic> normalized) {
    // Critical fields that must not be empty
    final String rollno = normalized['rollno']?.toString() ?? '';
    final String name = normalized['name']?.toString() ?? '';
    final String id = normalized['id']?.toString() ?? '';

    return rollno.isNotEmpty && name.isNotEmpty && id.isNotEmpty;
  }

  /// Parse combined name field format: "rollno_name" (e.g., "23ece1031_Snehashish")
  /// Returns map with 'rollno' and 'name' keys
  Map<String, String> _parseNameField(String fullName) {
    if (fullName.isEmpty) {
      return {'rollno': '', 'name': ''};
    }

    // Check if the name contains underscore pattern (rollno_name)
    if (fullName.contains('_')) {
      final parts = fullName.split('_');
      if (parts.length >= 2) {
        final extractedRollno = parts[0].trim();
        // Join remaining parts in case name contains underscores
        final extractedName = parts.sublist(1).join('_').trim();

        print(
          '[Firebase Service] Parsed name field: "$fullName" -> rollno: "$extractedRollno", name: "$extractedName"',
        );
        return {'rollno': extractedRollno, 'name': extractedName};
      }
    }

    // If no underscore pattern found, return as name only
    return {'rollno': '', 'name': fullName};
  }

  /// Fetch student data by rollno (search key)
  /// Returns merged data from gate_passes and leave_requests
  Future<Map<String, dynamic>?> fetchStudentByRollNo(String rollNo) async {
    try {
      // Search in gate_passes collection
      final gatePassQuery = await _firestore
          .collection('gate_passes')
          .where('rollno', isEqualTo: rollNo)
          .limit(1)
          .get();

      if (gatePassQuery.docs.isNotEmpty) {
        final gatePassData = gatePassQuery.docs.first.data();
        print('[Firebase] Found gate_passes record for rollno: $rollNo');
        return _normalizeGatePassData(gatePassData);
      }

      // If not found in gate_passes, search in leave_requests
      final leaveQuery = await _firestore
          .collection('leave_requests')
          .where('rollno', isEqualTo: rollNo)
          .limit(1)
          .get();

      if (leaveQuery.docs.isNotEmpty) {
        final leaveData = leaveQuery.docs.first.data();
        print('[Firebase] Found leave_requests record for rollno: $rollNo');
        return _normalizeLeaveRequestData(leaveData);
      }

      print('[Firebase] No records found for rollno: $rollNo');
      return null;
    } catch (e) {
      print('[Firebase Error] Failed to fetch student data: $e');
      return null;
    }
  }

  /// Normalize gate_passes data to QRAuthenticator format
  Map<String, dynamic> _normalizeGatePassData(Map<String, dynamic> data) {
    // Extract rollno and name from combined name field if available
    final Map<String, String> parsedName = _parseNameField(
      data['name']?.toString() ?? '',
    );

    // Use rollNumber or rollno from Firebase, fall back to parsed name
    final String rollno = (data['rollNumber']?.toString() ?? '').isNotEmpty
        ? data['rollNumber'].toString()
        : (data['rollno']?.toString() ?? '').isNotEmpty
            ? data['rollno'].toString()
            : parsedName['rollno']!;

    // Always use parsed name (just the name part, not rollno_name)
    final String name = parsedName['name']!.isNotEmpty
        ? parsedName['name']!
        : data['name']?.toString() ?? '';

    // Location: use comingFrom (actual Firebase field), fall back to destination
    final String location = (data['comingFrom']?.toString() ?? '').isNotEmpty
        ? data['comingFrom'].toString()
        : data['destination']?.toString() ?? '';

    return {
      'type': data['type']?.toString() ?? 'day_scholar',
      'name': name,
      'id': rollno,
      'rollno': rollno,
      'phone': data['phone']?.toString() ?? '',
      'degree': data['degree']?.toString() ?? '',
      'status': data['status']?.toString() ?? 'active',
      'comingFrom': data['comingFrom']?.toString() ?? '',
      'hostel': data['hostel']?.toString() ?? '',
      'roomNumber': data['roomNumber']?.toString() ?? '',
      'createdAt': data['createdAt'] ?? '',
      'scanCount': data['scanCount'] ?? 0,
      'location': location,
      'security': null,
    };
  }

  /// Normalize leave_requests data to QRAuthenticator format
  Map<String, dynamic> _normalizeLeaveRequestData(Map<String, dynamic> data) {
    // Extract rollno and name from combined name field if available
    final Map<String, String> parsedName = _parseNameField(
      data['name']?.toString() ?? '',
    );

    // Use parsed values if available and original fields are empty
    final String rollno = (data['rollno']?.toString() ?? '').isEmpty
        ? parsedName['rollno']!
        : data['rollno']?.toString() ?? '';

    // Always use parsed name (just the name part, not rollno_name)
    final String name = parsedName['name']!.isNotEmpty
        ? parsedName['name']!
        : data['name']?.toString() ?? '';

    return {
      'type': 'leave',
      'name': name,
      'id': rollno,
      'rollno': rollno,
      'phone': data['phone']?.toString() ?? '',
      'leaving': data['leaving']?.toString() ?? '',
      'returning': data['returning']?.toString() ?? '',
      'duration': data['duration']?.toString() ?? '',
      'address': data['address']?.toString() ?? '',
      'reason': data['reason']?.toString() ?? '',
      'status': data['status']?.toString() ?? 'pending',
      'location': data['address']?.toString() ?? '',
      'createdAt': data['createdAt'] ?? '',
      'security': null,
    };
  }

  /// Batch fetch multiple students by rollno list
  Future<List<Map<String, dynamic>>> fetchMultipleByRollNo(
    List<String> rollNos,
  ) async {
    final results = <Map<String, dynamic>>[];

    for (final rollNo in rollNos) {
      final data = await fetchStudentByRollNo(rollNo);
      if (data != null) {
        results.add(data);
      }
    }

    return results;
  }

  /// Get all active students from gate_passes
  Future<List<Map<String, dynamic>>> fetchAllActiveStudents() async {
    try {
      final query = await _firestore
          .collection('gate_passes')
          .where('status', isEqualTo: 'active')
          .get();

      return query.docs
          .map((doc) => _normalizeGatePassData(doc.data()))
          .toList();
    } catch (e) {
      print('[Firebase Error] Failed to fetch all students: $e');
      return [];
    }
  }

  /// Get all leave requests
  Future<List<Map<String, dynamic>>> fetchAllLeaveRequests() async {
    try {
      final query = await _firestore
          .collection('leave_requests')
          .where('status', isEqualTo: 'pending')
          .get();

      return query.docs
          .map((doc) => _normalizeLeaveRequestData(doc.data()))
          .toList();
    } catch (e) {
      print('[Firebase Error] Failed to fetch leave requests: $e');
      return [];
    }
  }
}
