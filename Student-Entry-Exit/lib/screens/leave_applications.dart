import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LeaveApplicationsScreen extends StatelessWidget {
  // Changed from List to ValueListenable
  final ValueListenable<List<Map<String, dynamic>>> applicationsListenable;
  const LeaveApplicationsScreen({
    super.key,
    required this.applicationsListenable,
  });

  String _first(Map<String, dynamic> a, List<String> keys) {
    for (final k in keys) {
      if (a.containsKey(k) && a[k] != null) {
        final s = a[k].toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  bool _isLeave(Map<String, dynamic> a) {
    final type = _first(a, ['type', 'Type']).toLowerCase();
    if (type.contains('leave')) return true;
    final hasLeaving = a.keys.any(
      (k) => k.toString().toLowerCase().contains('leaving'),
    );
    final hasReturning = a.keys.any(
      (k) => k.toString().toLowerCase().contains('returning'),
    );
    return hasLeaving || hasReturning;
  }

  String _formatDateTime(String? s) {
    if (s == null) return '';
    final re = RegExp(
      r'(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4})\s*(?:at\s*)?(\d{1,2}:\d{2})?',
      caseSensitive: false,
    );
    final m = re.firstMatch(s);
    if (m != null) {
      final date = m.group(1)!;
      final time = m.group(2);
      return time == null ? date : '$date at $time';
    }
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    final columns = <String>[
      'Name',
      'Roll Number',
      'Phone Number',
      'Leaving',
      'Returning',
      'Duration',
      'Address',
      'Received',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Leave Applications')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        // Added ValueListenableBuilder here
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: applicationsListenable,
          builder: (context, allApplications, _) {
            final leaves = allApplications.where((a) => _isLeave(a)).toList();

            if (leaves.isEmpty) {
              return const Center(
                child: Text('No leave applications received yet.'),
              );
            }

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 900),
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 24,
                    headingRowHeight: 56,
                    dataRowHeight: 56,
                    columns: columns
                        .map(
                          (c) => DataColumn(
                            label: Text(
                              c,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    rows: leaves.map((a) {
                      final name = _first(a, [
                        'name',
                        'Name',
                        'full name',
                        'fullname',
                      ]);
                      final roll = _first(a, [
                        'roll number',
                        'Roll Number',
                        'roll',
                        'id',
                        'Id',
                      ]);
                      final phone = _first(a, [
                        'phone number',
                        'Phone Number',
                        'phone',
                        'mobile',
                      ]);
                      final leaving = _formatDateTime(
                        _first(a, ['leaving', 'Leaving', 'from']),
                      );
                      final returning = _formatDateTime(
                        _first(a, ['returning', 'Returning', 'to']),
                      );
                      final duration = _first(a, ['duration', 'Duration']);
                      final address = _first(a, [
                        'address',
                        'Address',
                        'location',
                        'Location',
                      ]);
                      final received = _first(a, [
                        'receivedAt',
                        'received_at',
                        'received',
                      ]);

                      Widget leavingWidget() {
                        if (leaving.isEmpty) {
                          return const Text(
                            '\u2014',
                            style: TextStyle(color: Colors.black45),
                          );
                        }
                        return SelectableText(
                          leaving,
                          style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }

                      Widget returningWidget() {
                        if (returning.isEmpty) {
                          return const Text(
                            '\u2014',
                            style: TextStyle(color: Colors.black45),
                          );
                        }
                        return Text(
                          returning,
                          style: const TextStyle(
                            color: Color(0xFFD32F2F),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }

                      final statusLabel = duration.isNotEmpty
                          ? 'Duration: $duration'
                          : '';

                      return DataRow(
                        cells: [
                          DataCell(SelectableText(name)),
                          DataCell(SelectableText(roll)),
                          DataCell(SelectableText(phone)),
                          DataCell(leavingWidget()),
                          DataCell(returningWidget()),
                          DataCell(SelectableText(duration)),
                          DataCell(SelectableText(address)),
                          DataCell(
                            statusLabel.isEmpty
                                ? SelectableText(received)
                                : Row(
                                    children: [
                                      SelectableText(received),
                                      const SizedBox(width: 8),
                                      Chip(
                                        label: Text(
                                          statusLabel,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        backgroundColor: Colors.amber.shade700,
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
