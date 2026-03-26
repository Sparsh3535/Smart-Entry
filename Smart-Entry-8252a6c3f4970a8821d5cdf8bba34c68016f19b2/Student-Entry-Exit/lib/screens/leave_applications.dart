import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

class LeaveApplicationsScreen extends StatefulWidget {
  final ValueListenable<List<Map<String, dynamic>>> applicationsListenable;
  const LeaveApplicationsScreen({
    super.key,
    required this.applicationsListenable,
  });

  @override
  State<LeaveApplicationsScreen> createState() => _LeaveApplicationsScreenState();
}

class _LeaveApplicationsScreenState extends State<LeaveApplicationsScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _cell(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      if (row.containsKey(k) && row[k] != null) {
        final s = row[k].toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  bool _isLeave(Map<String, dynamic> a) {
    final type = _cell(a, ['type', 'Type']).toLowerCase();
    if (type.contains('leave')) return true;
    final hasLeaving = a.keys.any(
      (k) => k.toString().toLowerCase().contains('leaving'),
    );
    final hasReturning = a.keys.any(
      (k) => k.toString().toLowerCase().contains('returning'),
    );
    return hasLeaving || hasReturning;
  }

  bool _matchesSearch(Map<String, dynamic> row) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final id = _cell(row, ['id', 'Id', 'roll', 'roll number', 'Roll Number', 'rollno']).toLowerCase();
    final name = _cell(row, ['name', 'Name', 'full name', 'fullname']).toLowerCase();
    return id.contains(q) || name.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Applications')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by Roll Number or Name...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
            ),
            // Table
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: widget.applicationsListenable,
                    builder: (context, allApplications, _) {
                      final leaves = allApplications
                          .where((a) => _isLeave(a))
                          .where(_matchesSearch)
                          .toList();

                      if (allApplications.where((a) => _isLeave(a)).isEmpty) {
                        return const Center(
                          child: Text('No leave applications received yet.'),
                        );
                      }
                      if (leaves.isEmpty) {
                        return const Center(
                          child: Text('No matching entries found.'),
                        );
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Builder(
                          builder: (ctx) {
                            final screenWidth = MediaQuery.of(ctx).size.width - 48;
                            final minW = screenWidth;
                            final colCount = 9;
                            final columnSpacing = math.max(
                              12.0,
                              (minW / math.max(1, colCount).toDouble()) * 0.7,
                            );
                            return ConstrainedBox(
                              constraints: BoxConstraints(minWidth: minW),
                              child: SingleChildScrollView(
                                child: DataTable(
                                  columnSpacing: columnSpacing,
                                  headingRowHeight: 64,
                                  dataRowHeight: 64,
                                  columns: const [
                                    DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Roll Number', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Phone Number', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Room Number', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Leaving', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Returning', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Duration', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Address', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Received', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: leaves.map((a) {
                                    final name = _cell(a, ['name', 'Name', 'full name', 'fullname']);
                                    final roll = _cell(a, ['roll number', 'Roll Number', 'roll', 'id', 'Id', 'rollno']);
                                    final phone = _cell(a, ['phone number', 'Phone Number', 'phone', 'mobile']);
                                    final roomNumber = _cell(a, ['roomNumber', 'room_number', 'RoomNumber']);
                                    final leaving = _cell(a, ['leaving', 'Leaving', 'from']);
                                    final returning = _cell(a, ['returning', 'Returning', 'to']);
                                    final duration = _cell(a, ['duration', 'Duration']);
                                    final address = _cell(a, ['address', 'Address', 'addressDuringLeave', 'location', 'Location']);
                                    final received = _cell(a, ['receivedAt', 'received_at', 'received']);

                                    Widget leavingWidget() {
                                      if (leaving.isEmpty) {
                                        return const Text('\u2014', style: TextStyle(color: Colors.black45));
                                      }
                                      return SelectableText(
                                        leaving,
                                        style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600, fontSize: 14),
                                      );
                                    }

                                    Widget returningWidget() {
                                      if (returning.isEmpty) {
                                        return const Text('\u2014', style: TextStyle(color: Colors.black45));
                                      }
                                      return Text(
                                        returning,
                                        style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w600, fontSize: 14),
                                      );
                                    }

                                    Widget durationWidget() {
                                      if (duration.isEmpty) return const SizedBox.shrink();
                                      return Chip(
                                        label: Text(duration, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                        backgroundColor: Colors.amber.shade700,
                                      );
                                    }

                                    const cellStyle = TextStyle(fontSize: 14);
                                    return DataRow(
                                      cells: [
                                        DataCell(SelectableText(name, style: cellStyle)),
                                        DataCell(SelectableText(roll, style: cellStyle)),
                                        DataCell(SelectableText(phone, style: cellStyle)),
                                        DataCell(SelectableText(roomNumber, style: cellStyle)),
                                        DataCell(leavingWidget()),
                                        DataCell(returningWidget()),
                                        DataCell(durationWidget()),
                                        DataCell(SelectableText(address, style: cellStyle)),
                                        DataCell(SelectableText(received, style: cellStyle)),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
