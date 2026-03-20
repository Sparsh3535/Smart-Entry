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
        final gatePassData =
            gatePassQuery.docs.first.data() as Map<String, dynamic>;
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
        final leaveData = leaveQuery.docs.first.data() as Map<String, dynamic>;
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
    return {
      'type': data['type'] ?? 'day_scholar',
      'name': data['name'] ?? '',
      'id': data['rollNumber'] ?? data['rollno'] ?? '',
      'rollno': data['rollno'] ?? '',
      'phone': data['phone'] ?? '',
      'degree': data['degree'] ?? '',
      'status': data['status'] ?? 'active',
      'studentId': data['studentId'] ?? '',
      'comingFrom': data['comingFrom'] ?? '',
      'createdAt': data['createdAt'] ?? '',
      'scanCount': data['scanCount'] ?? 0,
      // Add location if available, otherwise use comingFrom
      'location': data['location'] ?? data['comingFrom'] ?? 'Unknown',
      // Security field for future use
      'security': null,
    };
  }

  /// Normalize leave_requests data to QRAuthenticator format
  Map<String, dynamic> _normalizeLeaveRequestData(Map<String, dynamic> data) {
    return {
      'type': 'leave',
      'name': data['name'] ?? '',
      'id': data['rollno'] ?? '',
      'rollno': data['rollno'] ?? '',
      'phone': data['phone'] ?? '',
      'leaving': data['leaving'] ?? data['leaveDate'] ?? '',
      'returning': data['returning'] ?? data['returnDate'] ?? '',
      'duration': data['duration'] ?? '',
      'address': data['address'] ?? '',
      'reason': data['reason'] ?? '',
      'status': data['status'] ?? 'pending',
      'createdAt': data['createdAt'] ?? '',
      'security': null,
    };
  }

  /// Batch fetch multiple students by rollno list
  Future<List<Map<String, dynamic>>> fetchMultipleByRollNo(
      List<String> rollNos) async {
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
