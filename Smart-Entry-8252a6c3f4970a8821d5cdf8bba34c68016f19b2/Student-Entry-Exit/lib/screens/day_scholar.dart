import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

class DayScholarScreen extends StatefulWidget {
  final ValueListenable<List<Map<String, dynamic>>> applicationsListenable;
  const DayScholarScreen({super.key, required this.applicationsListenable});

  @override
  State<DayScholarScreen> createState() => _DayScholarScreenState();
}

class _DayScholarScreenState extends State<DayScholarScreen> {
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

  bool _matchesSearch(Map<String, dynamic> row) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final id = _cell(row, ['id', 'Id', 'roll', 'roll_no', 'rollno', 'Roll Number']).toLowerCase();
    final name = _cell(row, ['name', 'Name', 'fullName', 'fullname']).toLowerCase();
    return id.contains(q) || name.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Day scholar')),
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
                    builder: (context, rows, _) {
                      var filtered = rows.where(_matchesSearch).toList();

                      // After 9 PM: unfilled entries (missing outtime) go to top
                      if (DateTime.now().hour >= 21) {
                        filtered.sort((a, b) {
                          final aOut = _cell(a, ['outtime', 'out_time', 'outTime']).trim();
                          final bOut = _cell(b, ['outtime', 'out_time', 'outTime']).trim();
                          final aFilled = aOut.isNotEmpty ? 1 : 0;
                          final bFilled = bOut.isNotEmpty ? 1 : 0;
                          return aFilled.compareTo(bFilled); // unfilled (0) before filled (1)
                        });
                      }
                      if (rows.isEmpty) {
                        return const Center(
                          child: Text('No day scholar entries yet.'),
                        );
                      }
                      if (filtered.isEmpty) {
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
                            final colCount = 7;
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
                                    DataColumn(label: Text('Id', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('In Time', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Out Time', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Security', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: filtered.map((r) {
                                    final name = _cell(r, ['name', 'Name', 'fullName', 'fullname']);
                                    final id = _cell(r, ['id', 'Id', 'roll', 'roll_no', 'rollno', 'Roll Number']);
                                    final phone = _cell(r, ['phone', 'Phone', 'mobile', 'Phone Number']);
                                    final location = _cell(r, ['location', 'Location', 'comingFrom', 'address']);
                                    final intime = _cell(r, ['intime', 'in_time', 'inTime']);
                                    final outtime = _cell(r, ['outtime', 'out_time', 'outTime']);
                                    final security = _cell(r, ['security', 'Security']);

                                    String chipLabel0() {
                                      return security.isNotEmpty ? security : '';
                                    }

                                    Color chipColor() {
                                      final s = security.toLowerCase();
                                      if (s.contains('checked')) return Colors.green.shade600;
                                      if (s.contains('late')) return Colors.amber.shade700;
                                      if (s.contains('unverified') || s.contains('un')) return Colors.red.shade400;
                                      return Colors.grey.shade400;
                                    }

                                    Widget intimeWidget() {
                                      if (intime.isEmpty) return const SelectableText('');
                                      return SelectableText(
                                        intime,
                                        style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600, fontSize: 14),
                                      );
                                    }

                                    Widget outtimeWidget() {
                                      if (outtime.isEmpty) {
                                        return const Text('\u2014', style: TextStyle(color: Colors.black45));
                                      }
                                      return Text(
                                        outtime,
                                        style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w600, fontSize: 14),
                                      );
                                    }

                                    final chipLabel = chipLabel0();
                                    const cellStyle = TextStyle(fontSize: 14);
                                    return DataRow(
                                      cells: [
                                        DataCell(SelectableText(name, style: cellStyle)),
                                        DataCell(SelectableText(id, style: cellStyle)),
                                        DataCell(SelectableText(phone, style: cellStyle)),
                                        DataCell(SelectableText(location, style: cellStyle)),
                                        DataCell(intimeWidget()),
                                        DataCell(outtimeWidget()),
                                        DataCell(
                                          chipLabel.isEmpty
                                              ? const SizedBox.shrink()
                                              : Chip(
                                                  label: Text(chipLabel, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                                  backgroundColor: chipColor(),
                                                ),
                                        ),
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
