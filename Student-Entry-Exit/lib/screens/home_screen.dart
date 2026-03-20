import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../managers/day_scholar_manager.dart';
import '../managers/hostel_manager.dart';
import '../managers/leave_applications_manager.dart';
import '../managers/qr_authenticator.dart';
import '../managers/firebase_service.dart';
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
  late final DayScholarManager _dayScholarManager = DayScholarManager();
  late final HostelManager _hostelManager = HostelManager();
  late final LeaveApplicationsManager _leaveManager =
      LeaveApplicationsManager();
  late final QRAuthenticator _qrAuthenticator;
  final FirebaseService _firebaseService = FirebaseService();

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

  @override
  void initState() {
    super.initState();
    // Set up log callbacks for managers
    _dayScholarManager.logCallback = _log;
    _hostelManager.logCallback = _log;
    _leaveManager.logCallback = _log;
    // Initialize QR authenticator
    _qrAuthenticator = QRAuthenticator(
      dayScholarManager: _dayScholarManager,
      hostelManager: _hostelManager,
      leaveManager: _leaveManager,
    );
    _qrAuthenticator.logCallback = _log;
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

        _processBuffer(buffer, (newBuffer) {
          buffer = newBuffer;
        });
      },
      onDone: () {
        _log('Client disconnected: ${client.remoteAddress.address}');
        if (buffer.trim().isNotEmpty) {
          _processBufferLine(buffer.trim());
          buffer = '';
        }
      },
      onError: (e) {
        _log('Client read error: $e');
      },
      cancelOnError: true,
    );
  }

  /// Process buffer and extract complete lines
  void _processBuffer(String buffer, void Function(String) setBuffer) {
    String buf = buffer;
    while (buf.isNotEmpty) {
      final nlIndex = buf.indexOf('\n');
      if (nlIndex >= 0) {
        final line = buf.substring(0, nlIndex).trim();
        if (line.isNotEmpty) _processBufferLine(line);
        buf = buf.substring(nlIndex + 1);
        continue;
      }
      break;
    }
    setBuffer(buf);
  }

  /// Process individual line - either JSON or Firebase key lookup
  void _processBufferLine(String line) async {
    if (line.isEmpty) return;

    _log('Processing received data (${line.length} chars): ${line.length > 200 ? '${line.substring(0, 200)}...' : line}');

    // Check if it's JSON (starts with { or [)
    if (line.trim().startsWith('{') || line.trim().startsWith('[')) {
      _log('Detected JSON format - passing to QRAuthenticator');
      _qrAuthenticator.processLine(line);
      return;
    }

    // Check if it's a simple rollno key (alphanumeric, possibly with underscores/hyphens)
    final simpleKeyPattern = RegExp(r'^[a-zA-Z0-9_\-]+$');
    if (simpleKeyPattern.hasMatch(line)) {
      _log('Detected rollno key format: "$line" - fetching from Firebase');
      await _fetchAndProcessFromFirebase(line);
      return;
    }

    // Otherwise, treat as raw data and pass to QRAuthenticator
    _log('Treating as raw data - passing to QRAuthenticator');
    _qrAuthenticator.processLine(line);
  }

  /// Fetch student data from Firebase by rollno and process it
  Future<void> _fetchAndProcessFromFirebase(String rollNo) async {
    try {
      final studentData = await _firebaseService.fetchStudentByRollNo(rollNo);

      if (studentData != null) {
        _log('✓ Firebase lookup successful for rollno: $rollNo');
        _log('Fetched data type: ${studentData['type']}');
        
        // Convert the fetched data to JSON and pass to QRAuthenticator
        // This ensures the same processing pipeline
        final jsonData = jsonEncode(studentData);
        _qrAuthenticator.processLine(jsonData);
      } else {
        _log('✗ No student found in Firebase for rollno: $rollNo');
      }
    } catch (e) {
      _log('✗ Firebase lookup failed for rollno "$rollNo": $e');
    }
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
              onTap: () {
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: Column(
              children: [
                // First row: Day Scholar + Leave Applications
                Row(
                  children: [
                    // Day Scholar Block
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DayScholarScreen(
                                applicationsListenable:
                                    _dayScholarManager.notifier,
                              ),
                            ),
                          );
                        },
                        child: Card(
                          elevation: 4,
                          child: Container(
                            height: 200,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 48,
                                  color: Colors.blue,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Day Scholar',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_dayScholarManager.rows.length} Entries',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Leave Applications Block
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LeaveApplicationsScreen(
                                applicationsListenable: _leaveManager.notifier,
                              ),
                            ),
                          );
                        },
                        child: Card(
                          elevation: 4,
                          child: Container(
                            height: 200,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.assignment,
                                  size: 48,
                                  color: Colors.orange,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Leave Applications',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_leaveManager.rows.length} Applications',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Second row: Hosteller + Console
                Row(
                  children: [
                    // Hosteller Block
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => HostelScreen(
                                rowsListenable: _hostelManager.notifier,
                              ),
                            ),
                          );
                        },
                        child: Card(
                          elevation: 4,
                          child: Container(
                            height: 200,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.apartment,
                                  size: 48,
                                  color: Colors.green,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Hosteller',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_hostelManager.rows.length} Entries',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Console Block
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          _scaffoldKey.currentState?.showBottomSheet(
                            (context) => Container(
                              height: 400,
                              color: Colors.white,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      right: 8,
                                    ),
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildConsoleView(
                                      showControls: false,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Card(
                          elevation: 4,
                          child: Container(
                            height: 200,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.code,
                                  size: 48,
                                  color: Colors.purple,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Console',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_logs.length} Logs',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Console View Section (below blocks)
                Card(
                  elevation: 4,
                  child: Container(
                    height: 300,
                    width: double.infinity,
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Expanded(child: _buildConsoleView(showControls: false)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Spacer(),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear All Data'),
                              onPressed: _clear,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
}
