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
import '../managers/csv_service.dart';
import '../managers/local_storage_service.dart';
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

    // When all time fields are filled, delete the Firebase document (keep screen entry)
    _dayScholarManager.onEntryComplete = (docId) {
      _log('[AUTO-DELETE] Day Scholar entry complete — deleting Firebase doc: $docId');
      _firebaseService.deleteByDocumentId(docId);
    };
    _hostelManager.onEntryComplete = (docId) {
      _log('[AUTO-DELETE] Hostel entry complete — deleting Firebase doc: $docId');
      _firebaseService.deleteByDocumentId(docId);
    };
    _leaveManager.onEntryComplete = (docId) {
      _log('[AUTO-DELETE] Leave entry complete — deleting Firebase doc: $docId');
      _firebaseService.deleteByDocumentId(docId);
    };
    // Initialize QR authenticator
    _qrAuthenticator = QRAuthenticator(
      dayScholarManager: _dayScholarManager,
      hostelManager: _hostelManager,
      leaveManager: _leaveManager,
    );
    _qrAuthenticator.logCallback = _log;
    // Load persisted data from local storage (auto-clears if from previous day)
    // But first ensure CSV path is configured so exports work
    _startupSequence();
    Future.microtask(_startServer);
    _startAdbWatcher(); // simple watcher: wait-for-device then run reverse
  }

  /// Startup sequence: load CSV path → prompt if needed → then load data
  Future<void> _startupSequence() async {
    // Step 1: Load saved CSV path
    await CsvService().loadSavedPath();

    if (!CsvService().isPathConfigured) {
      // Step 2: Wait for first frame, then show path dialog
      // Use a Completer to wait until the user sets the path (or skips)
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCsvPathDialog(onDone: () {
          if (!completer.isCompleted) completer.complete();
        });
      });
      await completer.future;
    } else {
      _log('[CSV] Save path: ${CsvService().basePath}');
    }

    // Step 3: Now load saved data (CSV path is available for export)
    await _loadSavedData();
  }

  @override
  void dispose() {
    _stopServer();
    _hScroll.dispose();
    _portController.dispose();
    _stopAdbWatcher();
    super.dispose();
  }

  /// Load persisted data from all managers.
  /// Before loading, delete all stale day_scholar and hostel entries from Firebase.
  Future<void> _loadSavedData() async {
    _log('[STARTUP] Loading saved data from local storage...');

    // Delete ALL stale day_scholar and hostel entries from Firebase (midnight reset)
    final storage = LocalStorageService();
    final staleDs = await storage.getStaleDocIds('day_scholar');
    final staleHostel = await storage.getStaleDocIds('hostel');
    if (staleDs.isNotEmpty || staleHostel.isNotEmpty) {
      _log('[MIDNIGHT RESET] Deleting ${staleDs.length + staleHostel.length} stale entries from Firebase...');
      for (final docId in [...staleDs, ...staleHostel]) {
        await _firebaseService.deleteByDocumentId(docId);
      }
      _log('[MIDNIGHT RESET] ✓ All stale Firebase entries deleted');
    }

    // Now load (which exports CSV and clears old data)
    await _dayScholarManager.loadFromStorage();
    await _hostelManager.loadFromStorage();
    await _leaveManager.loadFromStorage();
    _log('[STARTUP] ✓ Local storage loaded (day_scholar: ${_dayScholarManager.rows.length}, hostel: ${_hostelManager.rows.length}, leave: ${_leaveManager.rows.length})');
  }

  /// Show dialog to set CSV save path
  void _showCsvPathDialog({VoidCallback? onDone}) {
    final pathController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.folder_open, color: Colors.deepPurple, size: 28),
              SizedBox(width: 12),
              Text('Set CSV Save Path'),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the folder path where attendance CSV files will be saved.\n'
                  'Subfolders (day_scholar, hostel, leave_application) will be created automatically.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pathController,
                  decoration: InputDecoration(
                    hintText: r'e.g. C:\Users\spars\Desktop\Attendance',
                    prefixIcon: const Icon(Icons.folder),
                    errorText: errorText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onDone?.call();
              },
              child: const Text('Skip'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final path = pathController.text.trim();
                if (path.isEmpty) {
                  setDialogState(() => errorText = 'Please enter a folder path');
                  return;
                }

                final success = await CsvService().setBasePath(path);
                if (success) {
                  _log('[CSV] Save path set: $path');
                  _log('[CSV] Subfolders created: day_scholar, hostel, leave_application');
                  if (mounted) Navigator.of(ctx).pop();
                  onDone?.call();
                } else {
                  setDialogState(() => errorText = 'Path does not exist. Please enter a valid folder path.');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
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

    _log(
      'Processing received data (${line.length} chars): ${line.length > 200 ? '${line.substring(0, 200)}...' : line}',
    );

    // Check if it's JSON (starts with { or [)
    if (line.trim().startsWith('{') || line.trim().startsWith('[')) {
      _log('Detected JSON format - parsing...');

      try {
        final jsonData = jsonDecode(line);

        // Check if it's a wrapper format like {"event":"qr_scan","value":"docId"}
        if (jsonData is Map && jsonData.containsKey('value')) {
          final valueField = jsonData['value']?.toString() ?? '';

          // Check if the value is a simple document ID (not a full object)
          final simpleKeyPattern = RegExp(r'^[a-zA-Z0-9_\-]+$');
          if (simpleKeyPattern.hasMatch(valueField) && valueField.isNotEmpty) {
            _log(
              'Detected wrapper JSON with docId value: "$valueField" - fetching from Firebase',
            );
            await _fetchAndProcessFromFirebase(valueField);
            return;
          }
        }

        // Check if it has type/name fields indicating full student data
        if (jsonData is Map &&
            (jsonData.containsKey('type') || jsonData.containsKey('name'))) {
          _log('Detected full student data JSON - passing to QRAuthenticator');
          _qrAuthenticator.processLine(line);
          return;
        }

        // Default: pass JSON to QRAuthenticator
        _log('Processing as standard JSON - passing to QRAuthenticator');
        _qrAuthenticator.processLine(line);
      } catch (e) {
        _log('JSON parse error: $e - treating as raw data');
        _qrAuthenticator.processLine(line);
      }
      return;
    }

    // Check if it's a simple key (alphanumeric, possibly with underscores/hyphens)
    // This is the Firestore document ID received from port 9000
    final simpleKeyPattern = RegExp(r'^[a-zA-Z0-9_\-]+$');
    if (simpleKeyPattern.hasMatch(line)) {
      _log('Detected Firestore docId format: "$line" - fetching from Firebase');
      await _fetchAndProcessFromFirebase(line);
      return;
    }

    // Otherwise, treat as raw data and pass to QRAuthenticator
    _log('Treating as raw data - passing to QRAuthenticator');
    _qrAuthenticator.processLine(line);
  }

  /// Fetch student data from Firebase by document ID and process it
  Future<void> _fetchAndProcessFromFirebase(String docId) async {
    try {
      _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _log('[PORT 9000] KEY RECEIVED: $docId');
      _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      _log('[FIREBASE] Fetching document from database...');
      final studentData = await _firebaseService.fetchByDocumentId(docId);

      if (studentData != null) {
        _log('');
        _log('✓✓✓ FIREBASE FETCH SUCCESSFUL ✓✓✓');
        _log('[DATA] Type: ${studentData['type']}');
        _log('[DATA] Name: ${studentData['name']}');
        _log('[DATA] ID/RollNo: ${studentData['id']}');
        _log('[DATA] Phone: ${studentData['phone']}');
        _log('[DATA] Location: ${studentData['location']}');
        _log('[DATA] Status: ${studentData['status']}');

        _log('');
        _log('[FULL DATA OBJECT]:');
        _log('[TYPE]: ${studentData['type']}');
        _log('[NAME]: ${studentData['name']}');
        _log('[ID]: ${studentData['id']}');
        _log('[ROLLNO]: ${studentData['rollno']}');
        _log('[PHONE]: ${studentData['phone']}');
        _log('[DEGREE]: ${studentData['degree']}');
        _log('[STATUS]: ${studentData['status']}');
        _log('[DESTINATION]: ${studentData['destination']}');
        _log('[HOSTEL]: ${studentData['hostel']}');
        _log('[ROOM_NUMBER]: ${studentData['roomNumber']}');
        _log('[LOCATION]: ${studentData['location']}');
        _log('[CREATED_AT]: ${studentData['createdAt']}');
        _log('[SCAN_COUNT]: ${studentData['scanCount']}');
        _log('[SECURITY]: ${studentData['security']}');

        // Pass the fetched data directly to QRAuthenticator as a Map
        // (no JSON encode/decode round-trip — avoids issues with non-serializable values)
        _log('');
        _log('[ROUTING] Passing data directly to QRAuthenticator for processing...');

        studentData['_docId'] = docId;
        _log('[DOCID] Set _docId=$docId on studentData');
        _qrAuthenticator.processMap(studentData);

        _log('✓ Processing complete');
      } else {
        _log('');
        _log('✗✗✗ FIREBASE FETCH FAILED ✗✗✗');
        _log('✗ No student found in Firebase for docId: $docId');
        _log('Please verify:');
        _log('  - Document ID is correct');
        _log('  - Document exists in gate_passes or leave_requests collection');
        _log('  - Firebase connection is working');
      }
    } catch (e) {
      _log('');
      _log('✗✗✗ ERROR DURING FIREBASE LOOKUP ✗✗✗');
      _log('✗ Firebase lookup failed for docId "$docId": $e');
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
                final currentPath = CsvService().basePath;
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Row(
                      children: const [
                        Icon(Icons.settings, size: 24),
                        SizedBox(width: 10),
                        Text('Settings'),
                      ],
                    ),
                    content: SizedBox(
                      width: 500,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CSV Offline Copies Location',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      currentPath != null ? Icons.check_circle : Icons.warning_amber,
                                      color: currentPath != null ? Colors.green : Colors.orange,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      currentPath != null ? 'Path configured' : 'Not configured',
                                      style: TextStyle(
                                        color: currentPath != null ? Colors.green : Colors.orange,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                if (currentPath != null) ...[
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    currentPath,
                                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Subfolders: day_scholar, hostel, leave_application',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close'),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.edit, size: 16),
                        label: Text(currentPath != null ? 'Change Path' : 'Set Path'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showCsvPathDialog();
                        },
                      ),
                    ],
                  ),
                );
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
