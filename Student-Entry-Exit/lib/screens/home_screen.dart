import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../managers/day_scholar_manager.dart';
import '../managers/hostel_manager.dart';
import '../managers/leave_applications_manager.dart';
import '../managers/data_utils.dart';
import 'day_scholar.dart';
import 'leave_applications.dart';
import 'hostel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Initialize managers
  late final DayScholarManager _dayScholarManager = DayScholarManager();
  late final HostelManager _hostelManager = HostelManager();
  late final LeaveApplicationsManager _leaveManager =
      LeaveApplicationsManager();

  ServerSocket? _server;
  bool _listening = false;
  int _port = 9000;
  final ScrollController _hScroll = ScrollController();
  final TextEditingController _portController = TextEditingController(
    text: '9000',
  );
  // Optional in-memory override for the current security person's name.
  String? _securityOverride;

  // Simple adb watcher (wait-for-device -> run adb reverse)
  Process? _adbWatcherProcess;
  bool _adbWatcherRunning = false;

  // console logs
  final List<String> _logs = [];

  // UI state — default to console as requested
  String _navSelection = 'console'; // 'console' | 'table' | 'settings' etc.

  // fixed column keys and labels in desired order
  static const List<String> _colKeys = [
    'name',
    'id',
    'phone',
    'location',
    'intime',
    'outtime',
    'security',
  ];
  static const Map<String, String> _colLabels = {
    'name': 'Name',
    'id': 'Id',
    'phone': 'Phone',
    'location': 'Location',
    'intime': 'In Time',
    'outtime': 'Out Time',
    'security': 'Security',
  };

  @override
  void initState() {
    super.initState();
    // Set up log callbacks for managers
    _dayScholarManager.logCallback = _log;
    _hostelManager.logCallback = _log;
    _leaveManager.logCallback = _log;
    Future.microtask(_startServer);
    _startAdbWatcher(); // simple watcher: wait-for-device then run reverse
  }

  @override
  void dispose() {
    _stopServer();
    _hScroll.dispose();
    _portController.dispose();
    _stopAdbWatcher();
    super.dispose();
  }

  void _log(String s) {
    final line = '${DateTime.now().toIso8601String()} - $s';
    debugPrint(line);
    setState(() {
      _logs.insert(0, line);
      if (_logs.length > 2000) _logs.removeRange(2000, _logs.length);
    });
  }

  Future<void> _startServer() async {
    if (_listening) return;
    final portCandidate = int.tryParse(_portController.text) ?? _port;
    _port = portCandidate;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      _listening = true;
      _log('Server bound to ${_server!.address.address}:${_server!.port}');
      setState(() {});
      _server!.listen(
        _handleClient,
        onError: (e) {
          _log('Server error: $e');
        },
        onDone: () {
          _log('Server closed');
        },
      );
    } catch (e) {
      _log('Failed to bind server on port $_port: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start server on port $_port: $e')),
        );
      }
    }
  }

  Future<void> _stopServer() async {
    if (!_listening) return;
    try {
      await _server?.close();
      _log('Server closed manually');
    } catch (e) {
      _log('Error closing server: $e');
    }
    _server = null;
    _listening = false;
    setState(() {});
  }

  void _handleClient(Socket client) {
    _log(
      'Client connected: ${client.remoteAddress.address}:${client.remotePort}',
    );
    String buffer = '';

    client.listen(
      (List<int> data) {
        final snippet = utf8.decode(
          data.length <= 200 ? data : data.sublist(0, 200),
          allowMalformed: true,
        );
        // use double quotes and escape so inner single-quote usage doesn't break parsing
        _log(
          "Raw chunk bytes=${data.length}, text-snippet=\"${snippet.replaceAll('\n', '\\n')}\"",
        );
        final chunk = utf8.decode(data, allowMalformed: true);
        buffer += chunk;

        _processBuffer(
          bufferHolder: () => buffer,
          bufferSetter: (s) => buffer = s,
          clientAddr: client.remoteAddress.address,
        );
      },
      onDone: () {
        _log('Client disconnected: ${client.remoteAddress.address}');
        if (buffer.trim().isNotEmpty) {
          _processLine(buffer.trim());
          buffer = '';
        }
      },
      onError: (e) {
        _log('Client read error: $e');
      },
      cancelOnError: true,
    );
  }

  void _processBuffer({
    required String Function() bufferHolder,
    required void Function(String) bufferSetter,
    String? clientAddr,
  }) {
    String buf = bufferHolder();
    while (buf.isNotEmpty) {
      final nlIndex = buf.indexOf('\n');
      if (nlIndex >= 0) {
        final line = buf.substring(0, nlIndex).trim();
        if (line.isNotEmpty) _processLine(line);
        buf = buf.substring(nlIndex + 1);
        continue;
      }
      final firstNonWs = _firstNonWhitespaceIndex(buf);
      if (firstNonWs < 0) {
        buf = '';
        break;
      }
      final startChar = buf[firstNonWs];
      if (startChar == '{' || startChar == '[') {
        final endIndex = _findJsonEnd(buf, firstNonWs);
        if (endIndex >= 0) {
          final jsonStr = buf.substring(firstNonWs, endIndex + 1);
          _processLine(jsonStr);
          buf = buf.substring(endIndex + 1);
          continue;
        }
        break;
      }
      _processLine(buf.trim());
      buf = '';
      break;
    }
    bufferSetter(buf);
  }

  int _firstNonWhitespaceIndex(String s) {
    for (var i = 0; i < s.length; i++) {
      if (s[i].trim().isNotEmpty) return i;
    }
    return -1;
  }

  int _findJsonEnd(String s, int start) {
    final openChar = s[start];
    final closeChar = (openChar == '{') ? '}' : ']';
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < s.length; i++) {
      final ch = s[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == '\\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      } else {
        if (ch == '"') {
          inString = true;
          continue;
        }
        if (ch == openChar) {
          depth++;
        } else if (ch == closeChar) {
          depth--;
          if (depth == 0) return i;
        }
      }
    }
    return -1;
  }

  void _processLine(String line) {
    if (line.isEmpty) return;
    _log(
      'Processing line (${line.length} chars): ${line.length > 200 ? '${line.substring(0, 200)}...' : line}',
    );
    try {
      final decoded = jsonDecode(line);
      if (decoded is List) {
        for (final e in decoded) {
          _processData(e);
        }
      } else {
        _processData(decoded);
      }
      _log('Parsed JSON successfully');
    } catch (e) {
      _processData({'raw': line});
      _log('Failed JSON parse — stored raw');
    }
  }

  /// Process incoming data and route to appropriate manager
  void _processData(dynamic obj) {
    Map<String, dynamic> raw;
    if (obj is Map<String, dynamic>) {
      raw = Map<String, dynamic>.from(obj);
    } else {
      raw = {'value': obj?.toString()};
    }

    // If value contains key:value block, parse and merge into raw
    final kvFromValue = parseKeyValueBlock(raw['value'] ?? raw);
    if (kvFromValue.isNotEmpty) {
      kvFromValue.forEach((k, v) {
        // prefer existing explicit keys in raw; otherwise inject parsed value
        if (!raw.containsKey(k) ||
            raw[k] == null ||
            raw[k].toString().trim().isEmpty) {
          raw[k] = v;
        }
        // also add a capitalized variants to help older lookups
        final cap = _capitalizedKey(k);
        if (!raw.containsKey(cap) ||
            raw[cap] == null ||
            raw[cap].toString().trim().isEmpty) {
          raw[cap] = v;
        }
      });
    }

    // If this data has a Type and it routes to leave/day/hostel, let routing handle it.
    if (_routeByType(raw)) return;

    // Default: treat as generic entry (shouldn't normally reach here)
    _log('Unrouted data: ${raw.toString().substring(0, 100)}');
  }

  void _clear() {
    setState(() {
      _hostelManager.clear();
      _dayScholarManager.clear();
      _leaveManager.clear();
      _logs.insert(
        0,
        '${DateTime.now().toIso8601String()} - All tables cleared',
      );
    });
  }

  List<DataColumn> _buildColumns() {
    return _colKeys
        .map((k) => DataColumn(label: Text(_colLabels[k] ?? k)))
        .toList();
  }

  List<DataRow> _buildRows() {
    return _hostelManager.rows.map((r) {
      // helper to get string safely
      String sval(dynamic v) => v == null ? '' : v.toString();
      const cellStyle = TextStyle(fontSize: 14);

      final name = sval(r['name']);
      final id = sval(r['id']);
      final phone = sval(r['phone']);
      final location = sval(r['location']);
      final intime = sval(r['intime']);
      final outtime = sval(r['outtime']);
      final security = sval(r['security']);

      // security chip color resolution
      Color chipColor() {
        final s = security.toLowerCase();
        if (s.contains('checked')) return Colors.green.shade600;
        if (s.contains('late')) return Colors.amber.shade700;
        if (s.contains('unverified') || s.contains('un')) {
          return Colors.red.shade400;
        }
        // fallback based on presence: if intime present and outtime empty -> checked in
        if (intime.isNotEmpty && outtime.isEmpty) return Colors.green.shade600;
        return Colors.grey.shade400;
      }

      String chipLabel0() {
        if (security.isNotEmpty) return security;
        if (intime.isNotEmpty && outtime.isEmpty) return 'Checked In';
        return '';
      }

      Widget intimeWidget() {
        if (intime.isEmpty) return const SelectableText('');
        return SelectableText(
          intime,
          style: const TextStyle(
            color: Color(0xFF2E7D32),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        );
      }

      Widget outtimeWidget() {
        if (outtime.isEmpty) {
          return const Text('\u2014', style: TextStyle(color: Colors.black45));
        }
        return Text(
          outtime,
          style: const TextStyle(
            color: Color(0xFFD32F2F),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        );
      }

      final chipLabel = chipLabel0();

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
                    label: Text(
                      chipLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    backgroundColor: chipColor(),
                  ),
          ),
        ],
      );
    }).toList();
  }

  Widget _buildDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _dashCard('Hostel', '${_hostelManager.rows.length}'),
            const SizedBox(width: 12),
            // Day scholar card — opens separate screen
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DayScholarScreen(
                      applicationsListenable: _dayScholarManager.notifier,
                    ),
                  ),
                );
              },
              child: _dashCard(
                'Day scholar',
                '${_dayScholarManager.rows.length}',
              ),
            ),
            const SizedBox(width: 12),
            // Leave Applications card — opens separate screen
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LeaveApplicationsScreen(
                      applicationsListenable: _leaveManager.notifier,
                    ),
                  ),
                );
              },
              child: _dashCard(
                'Leave Applications',
                '${_leaveManager.rows.length}',
              ),
            ),
            const SizedBox(width: 12),
            // Security login card — shows current security name in a dialog
            InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Security login'),
                    content: Text(
                      'Current security: ${_currentSecurityName()}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
              child: _dashCard('Security login', 'View'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick actions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.play_circle),
                      label: const Text('Start Server'),
                      onPressed: _listening ? null : _startServer,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.stop_circle),
                      label: const Text('Stop Server'),
                      onPressed: _listening ? _stopServer : null,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear Table'),
                      onPressed: _clear,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // SECURITY LOGIN SECTION - visible card so it's not hidden inside the
        // dashboard row. Shows the current security person and provides a
        // button to view/change (view opens dialog). UI-only; does not
        // persist changes beyond runtime.
        Card(
          color: Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Security login',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Text(
                  _currentSecurityName(),
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Security login'),
                        content: Text(
                          'Current security: ${_currentSecurityName()}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('View'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dashCard(
    String title,
    String value, {
    double width = 140,
    Color? color,
  }) {
    return Card(
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 16, color: color ?? Colors.black),
            ),
          ],
        ),
      ),
    );
  }

  // Left navigation pane
  Widget _buildLeftPane() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.black87,
              child: Row(
                children: const [
                  Icon(Icons.dashboard, color: Colors.white),
                  SizedBox(width: 12),
                  Text(
                    'Dashboard',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.assignment),
              title: const Text('Leave Applications'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LeaveApplicationsScreen(
                      applicationsListenable: _leaveManager.notifier,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Console'),
              selected: _navSelection == 'console',
              onTap: () {
                setState(() => _navSelection = 'console');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Hostel'),
              selected: _navSelection == 'hostel_table',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        HostelScreen(rowsListenable: _hostelManager.notifier),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Day scholar'),
              selected: _navSelection == 'day_scholar',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DayScholarScreen(
                      applicationsListenable: _dayScholarManager.notifier,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Security login'),
              onTap: () {
                Navigator.of(context).pop();
                // show editable dialog to set security name (in-memory)
                final ctl = TextEditingController(text: _currentSecurityName());
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Security login'),
                    content: TextField(
                      controller: ctl,
                      decoration: const InputDecoration(
                        labelText: 'Security name',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _securityOverride = ctl.text.trim();
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              selected: _navSelection == 'settings',
              onTap: () {
                setState(() => _navSelection = 'settings');
                Navigator.of(context).pop();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Navigator.of(context).pop();
                showAboutDialog(
                  context: context,
                  applicationName: 'Attendance Dashboard',
                  children: [
                    const Text(
                      'Receives JSON over TCP and shows attendance records.',
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Console widget reused for main view and drawer
  Widget _buildConsoleView({bool showControls = true}) {
    return Column(
      children: [
        if (showControls)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                const Text(
                  'Console',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy console',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    final txt = _logs.join('\n');
                    Clipboard.setData(ClipboardData(text: txt));
                    _log('Console copied to clipboard');
                  },
                ),
                IconButton(
                  tooltip: 'Clear console',
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    setState(() {
                      _logs.clear();
                    });
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: _logs.isEmpty
              ? const Center(child: Text('No logs yet.'))
              : ListView.builder(
                  reverse: true,
                  itemCount: _logs.length,
                  itemBuilder: (context, idx) {
                    final text = _logs[idx];
                    final isConn =
                        text.contains('Client connected') ||
                        text.contains('Client disconnected');
                    return ListTile(
                      dense: true,
                      title: Text(
                        text,
                        style: TextStyle(
                          fontSize: 12,
                          color: isConn ? Colors.blue : Colors.black87,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    if (_navSelection == 'console') {
      // show dashboard above console so the Day scholar card is visible and tappable
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              // dashboard (cards + quick actions)
              _buildDashboard(),
              const SizedBox(height: 8),
              // console area expands to fill remaining space
              Expanded(child: _buildConsoleView(showControls: true)),
            ],
          ),
        ),
      );
    } else if (_navSelection == 'table') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: _hostelManager.rows.isEmpty
              ? const Center(child: Text('No hostel data received yet.'))
              : Scrollbar(
                  controller: _hScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    child: Builder(
                      builder: (ctx) {
                        final screenWidth = MediaQuery.of(ctx).size.width - 48;
                        // Use available screen width as the table min width so the
                        // table does not exceed the viewport and require extra
                        // horizontal scrolling. Keep a small minimum so very
                        // narrow screens still render reasonably.
                        final minW = screenWidth;
                        final colCount = _colKeys.length;
                        // Slightly reduce column spacing so more columns fit on
                        // typical screens while keeping the layout readable.
                        final columnSpacing = math.max(
                          12.0,
                          (minW / math.max(1, colCount).toDouble()) * 0.7,
                        );
                        return ConstrainedBox(
                          constraints: BoxConstraints(minWidth: minW),
                          child: SingleChildScrollView(
                            child: DataTable(
                              columns: _buildColumns(),
                              rows: _buildRows(),
                              columnSpacing: columnSpacing,
                              dataRowHeight: 64,
                              headingRowHeight: 64,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      );
    } else {
      // settings: show listening status here only
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Settings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: Icon(
                      _listening ? Icons.stop_circle : Icons.play_circle,
                    ),
                    label: Text(_listening ? 'Stop' : 'Start'),
                    onPressed: () {
                      if (_listening) {
                        _stopServer();
                      } else {
                        _startServer();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'Server status:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _listening ? 'Listening' : 'Stopped',
                    style: TextStyle(
                      color: _listening ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear Table'),
                onPressed: _clear,
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildLeftPane(), // left pane (hamburger)
      drawerEnableOpenDragGesture: false,
      // removed endDrawer so the right-side three-line icon is gone
      appBar: AppBar(
        // show only the hamburger (left) and title
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Hostel Entry/Out'),
        actions: const [], // no top-right actions
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(child: _buildMainContent()),
            const SizedBox(height: 8),
            // Security card: shows the current security person's name (read-only UI)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    const Text(
                      'Security',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _currentSecurityName(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Determine the current security person's name from recent rows.
  // Scans hostel rows then dayRows for the most recent non-empty 'security' value.
  String _currentSecurityName() {
    // If user set an explicit override via the Security login, prefer it.
    if (_securityOverride != null && _securityOverride!.trim().isNotEmpty) {
      return _securityOverride!.trim();
    }
    for (var i = _hostelManager.rows.length - 1; i >= 0; i--) {
      final s = _hostelManager.rows[i]['security'];
      if (s != null) {
        final ss = s.toString().trim();
        if (ss.isNotEmpty) return ss;
      }
    }
    for (var i = _dayScholarManager.rows.length - 1; i >= 0; i--) {
      final s = _dayScholarManager.rows[i]['security'];
      if (s != null) {
        final ss = s.toString().trim();
        if (ss.isNotEmpty) return ss;
      }
    }
    return 'Unknown';
  }

  // Simple watcher that uses `adb wait-for-device` and runs `adb reverse` when a device appears.
  // This is lightweight and runs in the background while the app is open.
  void _startAdbWatcher() {
    if (_adbWatcherRunning) return;
    _adbWatcherRunning = true;

    // fire-and-forget loop
    Future(() async {
      while (_adbWatcherRunning) {
        try {
          _log('ADB watcher: waiting for device (adb wait-for-device)...');
          // start adb wait-for-device which blocks until a device becomes online
          final proc = await Process.start('adb', [
            'wait-for-device',
          ], runInShell: true);
          _adbWatcherProcess = proc;
          // wait until process exits (means device appeared)
          final exit = await proc.exitCode;
          if (!_adbWatcherRunning) break;
          _log(
            'ADB watcher: device detected (wait-for-device exit=$exit) — running reverse',
          );

          // run reverse for the configured port
          final rev = await Process.run('adb', [
            'reverse',
            'tcp:$_port',
            'tcp:$_port',
          ], runInShell: true);
          _log(
            'adb reverse exit=${rev.exitCode} stdout=${rev.stdout} stderr=${rev.stderr}',
          );
        } catch (e) {
          _log('ADB watcher error: $e');
        }
        // small pause to avoid tight loop if adb returns immediately
        await Future.delayed(const Duration(seconds: 2));
      }
    });
  }

  void _stopAdbWatcher() {
    _adbWatcherRunning = false;
    try {
      _adbWatcherProcess?.kill();
    } catch (_) {}
    _adbWatcherProcess = null;
  }

  String _capitalizedKey(String k) {
    if (k.isEmpty) return k;
    final parts = k.split(RegExp(r'\s+'));
    return parts
        .map((p) => p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1)))
        .join(' ');
  }

  /// Route incoming raw map/text by its Type key.
  /// Returns true if routed (so caller doesn't add a generic row).
  bool _routeByType(Map<String, dynamic> raw) {
    // try direct keys first
    String? type = firstString(raw, ['type', 'Type']);
    final kv = parseKeyValueBlock(raw);
    type ??= kv['type'];
    if (type == null) return false;
    final t = type.toLowerCase();

    // prefer possible value string for leave parsing
    final possibleValue = raw['value'] ?? kv['value'];

    // Leave
    if (t.contains('leave')) {
      final pl =
          _leaveManager.parseLeaveApplication(raw) ??
          _leaveManager.parseLeaveApplication(possibleValue);
      if (pl != null) {
        _leaveManager.addLeaveApplication(pl);
        setState(() {}); // trigger UI update
        return true;
      }
      return false;
    }

    // Hostel
    if (t.contains('hostel') || t.contains('hosteller')) {
      final name = firstString(raw, ['name', 'Name']) ?? kv['name'];
      final id =
          firstString(raw, ['id', 'Id', 'roll', 'roll_no', 'rollno']) ??
          kv['roll number'] ??
          kv['roll'];
      final phone =
          firstString(raw, ['phone', 'Phone', 'mobile']) ??
          kv['phone number'] ??
          kv['phone'];
      final location =
          firstString(raw, ['location', 'Location', 'address']) ??
          kv['location'];
      final minimal = <String, dynamic>{
        'name': name,
        'id': id,
        'phone': phone,
        'location': location,
      };
      _hostelManager.addOrUpdateRow(minimal);
      setState(() {}); // trigger UI update
      return true;
    }

    // Day scholar
    if (t.contains('day') || t.contains('scholar')) {
      final name = firstString(raw, ['name', 'Name']) ?? kv['name'];
      final id =
          firstString(raw, ['id', 'Id', 'roll', 'roll_no', 'rollno']) ??
          kv['roll number'] ??
          kv['roll'];
      final phone =
          firstString(raw, ['phone', 'Phone', 'mobile']) ??
          kv['phone number'] ??
          kv['phone'];
      final location =
          firstString(raw, ['location', 'Location', 'address']) ??
          kv['location'];
      final minimal = <String, dynamic>{
        'name': name,
        'id': id,
        'phone': phone,
        'location': location,
      };
      _dayScholarManager.addOrUpdateRow(minimal);
      setState(() {}); // trigger UI update
      return true;
    }

    return false;
  }
}
