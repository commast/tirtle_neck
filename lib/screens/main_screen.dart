import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants.dart';
import '../models/posture_state.dart';
import '../models/posture_snapshot.dart';
import '../models/sensor_posture.dart';
import '../models/title_system.dart';
import '../services/sensor_classifier.dart';
import '../services/overlay_channel.dart';
import '../services/pose_analyzer_channel.dart';
import '../services/native_camera_channel.dart';
import 'home_tab.dart';
import 'report_tab.dart';
import 'camera_tab.dart';
import 'reward_tab.dart';
import 'profile_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int               _tabIndex  = 0;
  WebSocketChannel? _channel;
  PostureState      _data      = PostureState.initial;
  bool              _connected = false;
  late AnimationController _warnAnim;

  final List<double>              _scoreHistory = [];
  final Map<String, List<double>> _subHistory   = {
    'pitch': [], 'eye': [], 'vis': [], 'z': [],
  };

  // 리포트용 스냅샷
  final List<PostureSnapshot> _snapshots = [];

  // ── 주기적 카메라 캡처 ──────────────────────────────────────────
  CameraController?           _camCtrl;
  bool                        _captureActive  = false;
  bool                        _pendingCapture = false;
  Timer?                      _captureTimer;
  final List<PostureSnapshot> _captureHistory = [];
  DateTime?                   _lastCaptureTime;

  // 모바일 서버 IP
  String _serverIp = '';

  // 앱 백그라운드 여부 (센서 트리거 시 카메라 서비스 시작 판단용)
  bool _appInBackground = false;

  // ── 센서 자세 분류기 (Android 전용) ────────────────────────────
  SensorClassifier? _sensorClassifier;
  SensorPosture     _sensorPosture = SensorPosture.inactive;

  // ── 온디바이스 분석 모드 ─────────────────────────────────────────
  // true  → 서버 없이 폰 안에서 MediaPipe 직접 실행
  // false → 기존 Python WebSocket 서버 방식
  static const bool _useLocalAnalysis = true;

  // 연결 상태 관리
  bool   _isConnecting = false;
  Timer? _reconnectTimer;
  int    _reconnectDelay = 2; // 초 단위, 실패 시 점진적으로 증가

  static const _winTitle = '포스처가드 서버';

  // 플랫폼에 따라 URL 결정
  String get _wsUrl {
    if (Platform.isWindows) return kServerUrl;
    final ip = _serverIp.trim().isEmpty ? '192.168.0.1' : _serverIp.trim();
    return 'ws://$ip:$kServerPort/ws/mobile';
  }

  int get _todayScore {
    if (_snapshots.isEmpty) return 0;
    return (_snapshots.map((s) => s.score).reduce((a, b) => a + b) /
            _snapshots.length)
        .round();
  }

  @override
  void initState() {
    super.initState();
    _warnAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _loadHistory(); // 앱 시작 시 이전 기록 복원
    _initForegroundTask(); // 포그라운드 서비스 옵션 설정

    if (Platform.isWindows) {
      _startServer();
    } else if (!_useLocalAnalysis) {
      // 서버 방식: WebSocket 연결
      Future.delayed(const Duration(seconds: 1), _connect);
    }
    // 온디바이스 방식: WebSocket 연결 불필요, 모델만 초기화

    // 센서 분류기 + 포그라운드 서비스 시작 (Android 전용, 백그라운드 센서 유지)
    if (Platform.isAndroid) {
      _sensorClassifier = SensorClassifier(
        onPostureChanged: (p) {
          if (mounted) setState(() => _sensorPosture = p);
          OverlayChannel.update(p); // 네이티브 오버레이 상태 전송
        },
        onTurtleNeckDetected: _onTurtleNeckDetected,
      );
      Future.microtask(() async {
        await _sensorClassifier!.start();
        if (mounted) setState(() => _sensorPosture = SensorPosture.normal);
        await _startSensorForegroundService();
        await _setupOverlay();
        // 온디바이스 모드: MediaPipe 모델 초기화 (백그라운드)
        if (_useLocalAnalysis) {
          final ok = await PoseAnalyzerChannel.initialize();
          debugPrint('[LocalAnalysis] 모델 초기화 ${ok ? "성공" : "실패"}');
          if (mounted) setState(() => _connected = ok); // 연결 표시 재활용
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && Platform.isWindows) {
      _killServer();
    }

    // 백그라운드 상태 추적
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _appInBackground = true;
      // A안: 백그라운드 진입 시 preview만 멈추고 카메라 세션은 유지 시도
      // (CameraX가 STOPPED에서 해제하기 전에 pausePreview로 세션을 붙잡음)
      if (_captureActive && _camCtrl != null &&
          _camCtrl!.value.isInitialized) {
        try { _camCtrl!.pausePreview(); } catch (_) {}
      }
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
    }

    if (state == AppLifecycleState.resumed) {
      // 포그라운드 복귀 시 preview 재개 또는 카메라 재초기화
      if (_captureActive) {
        if (_camCtrl != null && _camCtrl!.value.isInitialized) {
          try { _camCtrl!.resumePreview(); } catch (_) {}
        } else {
          _ensureCameraReady();
        }
      }
      if (Platform.isAndroid) _setupOverlay();
      // CameraBackgroundService는 stopCapture()에서만 종료
      // resumed에서 종료하면 이후 백그라운드 촬영이 차단됨
    }
  }

  Future<void> _ensureCameraReady() async {
    if (_camCtrl != null && _camCtrl!.value.isInitialized) return;
    // 이전 컨트롤러가 있으면 먼저 해제 (해제 없이 새로 만들면 카메라 충돌)
    if (_camCtrl != null) {
      try { await _camCtrl!.dispose(); } catch (_) {}
      _camCtrl = null;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camCtrl = CameraController(cam, ResolutionPreset.low, enableAudio: false);
    await _camCtrl!.initialize();
  }

  // ── Windows 전용: 서버 시작/종료 ───────────────────────────────
  void _killServer() => _freePortSync(kServerPort);

  void _freePortSync(int port) {
    try {
      final result = Process.runSync('cmd', ['/c', 'netstat -ano | findstr :$port']);
      for (final line in result.stdout.toString().split('\n')) {
        if (line.contains(':$port ') && line.contains('LISTENING')) {
          final pid = line.trim().split(RegExp(r'\s+')).last.trim();
          if (pid.isNotEmpty) {
            Process.runSync('taskkill', ['/F', '/T', '/PID', pid]);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _startServer() async {
    await _freePortAsync(kServerPort);

    final serverDir = _resolveServerDir();
    if (serverDir == null) { _connect(); return; }

    try {
      await Process.run(
        'cmd',
        ['/c', 'start', _winTitle, 'cmd', '/k',
         'python -m uvicorn server:app --host 0.0.0.0 --port $kServerPort'],
        workingDirectory: serverDir,
      );
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 4));
    if (mounted) _connect();
  }

  Future<void> _freePortAsync(int port) async {
    try {
      final result = await Process.run('cmd', ['/c', 'netstat -ano | findstr :$port']);
      for (final line in result.stdout.toString().split('\n')) {
        if (line.contains(':$port ') && line.contains('LISTENING')) {
          final pid = line.trim().split(RegExp(r'\s+')).last.trim();
          if (pid.isNotEmpty) {
            await Process.run('taskkill', ['/F', '/T', '/PID', pid]);
          }
        }
      }
    } catch (_) {}
  }

  String? _resolveServerDir() {
    final candidates = [
      '${File(Platform.resolvedExecutable).parent.path}/server',
      '${Directory.current.path}/server',
    ];
    for (final path in candidates) {
      if (Directory(path).existsSync()) return path;
    }
    return null;
  }

  // ── 포그라운드 서비스 초기화 ──────────────────────────────────
  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:          'posture_guard_channel',
        channelName:        '포스처가드 자세 측정',
        channelDescription: '백그라운드에서 자세를 측정합니다.',
        onlyAlertOnce:      true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 서비스 유지용 이벤트 (2분 간격, 실제 캡처는 메인 isolate에서 처리)
        eventAction: ForegroundTaskEventAction.repeat(120000),
        autoRunOnBoot:  false,
        allowWifiLock:  true,
      ),
    );
  }

  // 앱 시작 시 포그라운드 서비스 시작 (센서 백그라운드 유지용)
  Future<void> _startSensorForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId:         256,
      notificationTitle: '포스처가드',
      notificationText:  '자세를 감지하고 있습니다.',
      callback:          _postureTaskCallback,
    );
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data == 'stop') stopCapture();
    });
  }

  // 카메라 캡처 시작 → 알림을 "측정 중"으로 업데이트
  Future<void> _startForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: '포스처가드 측정 중 🔴',
        notificationText:  '2분마다 자동 촬영합니다. 탭해서 앱 열기.',
        notificationButtons: [
          const NotificationButton(id: 'stop_btn', text: '측정 중지'),
        ],
      );
    } else {
      // 서비스가 없으면 새로 시작 (혹시 종료된 경우 대비)
      await FlutterForegroundTask.startService(
        serviceId:         256,
        notificationTitle: '포스처가드 측정 중 🔴',
        notificationText:  '2분마다 자동 촬영합니다. 탭해서 앱 열기.',
        notificationButtons: [
          const NotificationButton(id: 'stop_btn', text: '측정 중지'),
        ],
        callback: _postureTaskCallback,
      );
      FlutterForegroundTask.addTaskDataCallback((data) {
        if (data == 'stop') stopCapture();
      });
    }
  }

  // 카메라 캡처 중지 → 알림을 "감지 중"으로 복원 (서비스는 유지)
  Future<void> _stopForegroundService() async {
    await FlutterForegroundTask.updateService(
      notificationTitle: '포스처가드',
      notificationText:  '자세를 감지하고 있습니다.',
      notificationButtons: [],
    );
  }

  // ── 주기적 카메라 캡처 ──────────────────────────────────────────
  Future<void> startCapture() async {
    if (_captureActive) return;
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    // 로컬 분석 모드(Camera2)에서는 Flutter CameraController 불필요
    // _useLocalAnalysis = false(서버 방식)일 때만 초기화
    if (!_useLocalAnalysis) {
      try {
        await _ensureCameraReady();
      } catch (e) {
        debugPrint('[startCapture] 카메라 초기화 실패: $e');
        return;
      }
      if (_camCtrl == null || !_camCtrl!.value.isInitialized) return;
    }

    await WakelockPlus.enable();
    await _startForegroundService();
    if (Platform.isAndroid) await OverlayChannel.startCameraService();
    setState(() { _captureActive = true; _lastCaptureTime = null; });

    await _captureOnce(); // 즉시 첫 촬영 (calibrating일 수 있음)

    // calibration(5초) 직후 두 번째 촬영으로 즉시 점수 획득
    // 이후 촬영은 센서 거북목 감지로만 트리거
    Future.delayed(const Duration(seconds: 6), () {
      if (_captureActive) _captureOnce();
    });
  }

  void stopCapture() {
    _captureTimer?.cancel();
    _stopForegroundService();
    OverlayChannel.stopCameraService(); // 카메라 백그라운드 서비스 중지
    WakelockPlus.disable();
    setState(() { _captureActive = false; _pendingCapture = false; });
  }

  // 센서가 거북목 5초 지속 감지 시 자동 호출
  Future<void> _onTurtleNeckDetected() async {
    if (!_useLocalAnalysis && !_connected) return;
    debugPrint('[Trigger] 거북목 트리거 → captureActive=$_captureActive background=$_appInBackground');
    try {
      if (!_captureActive) {
        await startCapture();
      } else {
        await _captureOnce();
      }
    } catch (e) {
      debugPrint('[Trigger] 카메라 실행 오류: $e');
    }
  }

  // ── 네이티브 OverlayService 시작 ──────────────────────────────
  Future<void> _setupOverlay() async {
    if (!Platform.isAndroid) return;
    try {
      await OverlayChannel.start();
      await OverlayChannel.update(_sensorPosture);
    } catch (e) {
      debugPrint('[Overlay] 오버레이 시작 실패: $e');
    }
  }

  Future<void> _captureOnce() async {
    if (!_captureActive) return;
    if (!_useLocalAnalysis && !_connected) return;

    List<int>? bytes;

    if (_useLocalAnalysis) {
      // ── B안: Kotlin Camera2 직접 촬영 (Activity lifecycle 무관) ──
      debugPrint('[Capture] Native Camera2 촬영 시도');
      bytes = await NativeCameraChannel.captureImage();
      if (bytes == null) {
        debugPrint('[Capture] Native Camera2 실패');
        return;
      }
    } else {
      // ── 서버 방식: Flutter CameraController 사용 ─────────────────
      await _ensureCameraReady();
      if (_camCtrl == null || !_camCtrl!.value.isInitialized) return;
      try {
        if (_camCtrl!.value.isPreviewPaused) {
          try { await _camCtrl!.resumePreview(); } catch (_) {}
        }
        final xFile = await _camCtrl!.takePicture();
        bytes = await File(xFile.path).readAsBytes();
      } catch (e) {
        debugPrint('[Capture] Flutter camera 오류: $e');
        try { await _camCtrl?.dispose(); } catch (_) {}
        _camCtrl = null;
        return;
      }
    }

    setState(() {
      _pendingCapture  = true;
      _lastCaptureTime = DateTime.now();
    });

    if (_useLocalAnalysis) {
      final result = await PoseAnalyzerChannel.analyze(bytes);
      if (result != null) {
        _handlePostureResult(result);
      } else {
        setState(() => _pendingCapture = false);
      }
    } else {
      _channel?.sink.add(jsonEncode({'type': 'frame', 'frame': base64Encode(bytes)}));
    }
  }

  /// WebSocket 응답과 로컬 분석 결과를 동일하게 처리
  void _handlePostureResult(PostureState next) {
    if (!mounted) return;
    setState(() {
      _data = next;
      if (next.status == 'ok' || next.status == 'warning') {
        _scoreHistory.add(next.score.toDouble());
        if (_scoreHistory.length > kGraphMax) _scoreHistory.removeAt(0);
        for (final k in _subHistory.keys) {
          _subHistory[k]!.add(next.scores[k] ?? 1.0);
          if (_subHistory[k]!.length > kGraphMax) _subHistory[k]!.removeAt(0);
        }
        if (_pendingCapture) {
          _pendingCapture = false;
          final pitchDeg = (1.0 - (next.scores['pitch'] ?? 1.0)) * 20.0;
          final snap = PostureSnapshot(
            time:     _lastCaptureTime ?? DateTime.now(),
            score:    next.score,
            pitchDeg: pitchDeg,
          );
          _captureHistory.add(snap);
          _snapshots.add(snap);
          _saveHistory(); // 새 기록을 즉시 저장
          // 오버레이에 점수 표시 (사진 촬영 결과)
          if (Platform.isAndroid) {
            OverlayChannel.updateWithScore(_sensorPosture, next.score);
          }
        }
      } else {
        _pendingCapture = false;
      }
    });
  }

  // ── WebSocket 연결 ──────────────────────────────────────────────
  Future<void> _connect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    _reconnectTimer?.cancel();

    // 기존 채널을 null로 먼저 교체해야 onDone이 _onDisconnect를 재트리거하지 않음
    final old = _channel;
    _channel = null;
    old?.sink.close();

    try {
      final ch = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await ch.ready;
      if (!mounted) { _isConnecting = false; return; }

      _channel = ch;
      _isConnecting = false;
      _reconnectDelay = 2; // 성공 시 딜레이 초기화
      if (!_connected) setState(() => _connected = true);

      ch.stream.listen(
        (raw) {
          if (!mounted) return;
          final json = jsonDecode(raw as String) as Map<String, dynamic>;
          _handlePostureResult(PostureState.fromJson(json));
        },
        onError: (_) { if (_channel == ch) _onDisconnect(); },
        onDone:  ()  { if (_channel == ch) _onDisconnect(); },
        cancelOnError: true,
      );
    } catch (_) {
      _isConnecting = false;
      _onDisconnect();
    }
  }

  void _onDisconnect() {
    if (!mounted) return;
    final old = _channel;
    _channel = null;
    old?.sink.close();
    if (_connected) setState(() { _connected = false; _data = PostureState.initial; });

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      if (mounted && !_isConnecting) _connect();
    });
    // 지수적 백오프: 최대 30초
    if (_reconnectDelay < 30) _reconnectDelay = (_reconnectDelay * 2).clamp(2, 30);
  }

  // 모바일에서 IP 변경 시 재연결
  // ── 점수 기록 영속화 ──────────────────────────────────────────
  static const _kSnapKey = 'capture_history_v1';

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(
        _captureHistory.map((s) => s.toJson()).toList(),
      );
      await prefs.setString(_kSnapKey, json);
    } catch (e) {
      debugPrint('[Storage] 저장 실패: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kSnapKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => PostureSnapshot.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (!mounted) return;
      setState(() {
        _captureHistory
          ..clear()
          ..addAll(list);
        _snapshots
          ..clear()
          ..addAll(list);
      });
    } catch (e) {
      debugPrint('[Storage] 로드 실패: $e');
    }
  }

  void _onServerIpChanged(String ip) {
    setState(() => _serverIp = ip);
    _reconnectDelay = 2;
    _isConnecting = false;
    _reconnectTimer?.cancel();
    final old = _channel;
    _channel = null;
    old?.sink.close();
    _connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureTimer?.cancel();
    _reconnectTimer?.cancel();
    _camCtrl?.dispose();
    _channel?.sink.close();
    _warnAnim.dispose();
    WakelockPlus.disable();
    if (Platform.isWindows) _killServer();
    if (Platform.isAndroid) {
      _sensorClassifier?.dispose();
      FlutterForegroundTask.stopService();
      OverlayChannel.stop();
      if (_useLocalAnalysis) PoseAnalyzerChannel.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeTab(
        data: _data,
        connected: _connected,
        scoreHistory: _scoreHistory,
        todayScore: _todayScore,
        snapshotCount: _snapshots.length,
        currentTitle: _snapshots.isNotEmpty
            ? titleFromScore(ScoreAverages.from(_snapshots).overall)
            : null,
      ),
      ReportTab(data: _data, snapshots: _snapshots, todayScore: _todayScore),
      CameraTab(
        captureActive:   _captureActive,
        captureHistory:  _captureHistory,
        lastCaptureTime: _lastCaptureTime,
        connected:       _connected,
        onStart:         startCapture,
        onStop:          stopCapture,
      ),
      RewardTab(snapshots: _snapshots),
      ProfileTab(
        serverIp: _serverIp,
        onServerIpChanged: _onServerIpChanged,
        onOverlayStart: Platform.isAndroid ? _setupOverlay : null,
      ),
    ];

    return Scaffold(
      backgroundColor: kBg,
      body: screens[_tabIndex],
      floatingActionButton: FloatingActionButton(
        backgroundColor: _captureActive ? Colors.red : kGreen,
        elevation: 4,
        shape: const CircleBorder(),
        onPressed: () => setState(() => _tabIndex = 2),
        child: Icon(
          _captureActive ? Icons.fiber_manual_record : Icons.camera_alt_rounded,
          color: Colors.white, size: 26,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        elevation: 8,
        padding: EdgeInsets.zero,
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.home_rounded,          '홈'),
            _navItem(1, Icons.bar_chart_rounded,     '리포트'),
            const SizedBox(width: 56),
            _navItem(3, Icons.card_giftcard_rounded, '보상'),
            _navItem(4, Icons.person_rounded,        '프로필'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final active = _tabIndex == index;
    return InkWell(
      onTap: () => setState(() => _tabIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? kGreen : Colors.grey[400], size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(
              fontSize: 10,
              color: active ? kGreen : Colors.grey[400],
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }
}

// ── 포그라운드 서비스 태스크 핸들러 ─────────────────────────────────
// @pragma 필수: 별도 isolate에서 실행되므로 트리 쉐이킹 방지
@pragma('vm:entry-point')
void _postureTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_PostureTaskHandler());
}

class _PostureTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 서비스 시작 시 별도 작업 없음 (카메라는 메인 isolate에서 처리)
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 2분마다 호출 — 메인 isolate의 캡처 타이머가 실제 촬영을 담당
    // 서비스가 살아있음을 확인하는 heartbeat
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_btn') {
      // 알림의 '중지' 버튼 → 메인 isolate에 중지 신호 전송
      FlutterForegroundTask.sendDataToMain('stop');
    }
  }
}
