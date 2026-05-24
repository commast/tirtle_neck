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
import '../services/sensor_classifier.dart';
import '../services/context_detector.dart';
import '../services/overlay_channel.dart';
import '../services/camera_mode_settings.dart';
import '../services/posture_calibration.dart';
import '../services/headphone_head_tracker.dart';
import '../services/background_calibration_runner.dart';
import '../models/detected_context.dart';
import '../models/neck_risk.dart';
import '../services/pose_analyzer_channel.dart';
import '../services/native_camera_channel.dart';
import 'home_tab.dart';
import 'report_tab.dart';
import 'camera_tab.dart';
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

  // ── 센서 자세 분류기 + 컨텍스트 감지 (Android 전용) ──────────────
  SensorClassifier? _sensorClassifier;
  ContextDetector?  _contextDetector;
  DetectedContext   _detectedContext  = DetectedContext.normal;
  NeckRiskState     _riskState        = NeckRiskState.initial;
  final CameraModeSettings   _cameraSettings   = CameraModeSettings();
  final PostureCalibration   _calibration      = PostureCalibration();
  final HeadphoneHeadTracker _headphoneTracker = HeadphoneHeadTracker();
  final BackgroundCalibrationRunner _calRunner = BackgroundCalibrationRunner();
  bool _calibrationInProgress = false;
  // 현재 캡처가 거북목 트리거로 시작됐는지 여부. 히스토리 기록 분기에 사용.
  bool              _currentCaptureFromTurtleNeck = false;

  /// 디버그 화면(ProfileTab) 등에서 컨텍스트 상태를 구독할 수 있게 노출.
  ContextDetector?     get contextDetector  => _contextDetector;
  CameraModeSettings   get cameraSettings   => _cameraSettings;
  PostureCalibration   get calibration      => _calibration;
  HeadphoneHeadTracker get headphoneTracker => _headphoneTracker;
  NeckRiskState        get riskState        => _riskState;

  /// 오버레이 측정 버튼 탭 → 현재 컨텍스트에 대해 5초 백그라운드 캘리브레이션.
  Future<void> _handleOverlayCalibrateTapped() async {
    if (_calibrationInProgress) return;
    final mode = _detectedContext;
    if (!PostureCalibration.isCalibratableMode(mode)) {
      debugPrint('[Cal] ${mode.label} 모드는 측정 불가');
      return;
    }
    setState(() => _calibrationInProgress = true);
    debugPrint('[Cal] ${mode.label} 측정 시작');
    final result = await _calRunner.sample(onTick: (remaining) {
      // 카운트다운을 오버레이 측정 버튼에 표시
      _updateOverlay(calibrationCountdown: remaining);
    });
    if (result != null) {
      await _calibration.saveFor(mode, result);
      debugPrint('[Cal] ${mode.label} baseline 저장: '
          '${result.toStringAsFixed(1)}°');
    }
    if (mounted) setState(() => _calibrationInProgress = false);
    _updateOverlay(); // 버튼 숨김 또는 재표시
  }

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
      _contextDetector = ContextDetector();
      _sensorClassifier = SensorClassifier(
        onPostureChanged: (p) {
          _contextDetector?.updateSensorPosture(p);
        },
        onRiskChanged: (risk) {
          if (mounted) setState(() => _riskState = risk);
          _updateOverlay();
        },
        onTurtleNeckDetected: _onSustainedRiskDetected,
        calibration: _calibration,
      );
      _cameraSettings.load();
      _headphoneTracker.start(); // 실험 기능: 이어폰 헤드 트래커 — docs/HEADPHONE_TRACKER.md
      _calibration.load();
      // 오버레이 측정 버튼 탭 → 백그라운드 캘리브레이션 시작
      OverlayChannel.setCalibrateTappedHandler(_handleOverlayCalibrateTapped);
      Future.microtask(() async {
        // READ_PHONE_STATE 권한 미리 요청 (통화 중 감지용).
        await Permission.phone.request();
        // PACKAGE_USAGE_STATS는 보호된 권한 — 사용자가 ProfileTab에서 직접 설정 화면을 열어 허용해야 함.
        await _contextDetector!.start();
        _contextDetector!.context.addListener(() {
          final ctx = _contextDetector!.context.value;
          _sensorClassifier?.updateContext(ctx);
          if (mounted) setState(() => _detectedContext = ctx);
          _updateOverlay();
        });
        // 같은 컨텍스트 안에서 앱 이름이 바뀌어도 오버레이 라벨 갱신 (예: 유튜브 → 트위치).
        _contextDetector!.snapshot.addListener(() {
          _updateOverlay();
        });
        await _sensorClassifier!.start();
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
  Future<void> startCapture({bool fromTurtleNeck = false}) async {
    if (_captureActive) return;
    // 센서 트리거: 권한 다이얼로그를 띄우지 않고 조용히 스킵.
    // (유튜브/게임 사용 중에 우리 앱이 갑자기 포그라운드로 튀어나오는 것을 방지)
    // 사용자 수동 시작 시에만 권한 요청 다이얼로그 표시.
    final PermissionStatus status;
    if (fromTurtleNeck) {
      status = await Permission.camera.status;
      if (!status.isGranted) {
        debugPrint('[startCapture] 카메라 권한 없음 — 센서 트리거 무시 '
            '(사용자가 카메라 탭에서 직접 허용 필요)');
        return;
      }
    } else {
      status = await Permission.camera.request();
      if (!status.isGranted) return;
    }

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

    // 즉시 첫 촬영 (calibrating일 수 있음).
    // 거북목 트리거로 시작된 경우엔 그 캡처 결과가 히스토리에 들어가야 함.
    await _captureOnce(fromTurtleNeck: fromTurtleNeck);

    // calibration(5초) 직후 두 번째 촬영 — 캘리브레이션 점수는 히스토리 제외
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
  /// 위험 단계가 5초 유지되면 호출. 게임/영상 모드 + 사용자 옵트인 시에만 카메라 발사.
  Future<void> _onSustainedRiskDetected() async {
    final ctx = _detectedContext;
    final cameraAllowed = _cameraSettings.isCameraAllowedIn(ctx);
    debugPrint('[Trigger] 위험 지속 → ctx=${ctx.label} cameraAllowed=$cameraAllowed '
        'background=$_appInBackground');
    if (!cameraAllowed) {
      // 게임/영상 외 모드 OR 옵트인 안 함: 카메라 발사 안 함 (오버레이 위험 표시만 유지)
      return;
    }
    if (!_useLocalAnalysis && !_connected) return;
    try {
      if (!_captureActive) {
        await startCapture(fromTurtleNeck: true);
      } else {
        await _captureOnce(fromTurtleNeck: true);
      }
    } catch (e) {
      debugPrint('[Trigger] 카메라 실행 오류: $e');
    }
  }

  /// 분할 오버레이 갱신 — [모드 칩] [위험 칩] [(측정 버튼)]
  ///
  /// 측정 버튼 표시 정책:
  /// - 측정 가능한 모드(영상/게임/소셜/학습/책상)이고
  /// - 아직 해당 모드의 baseline이 없거나 [calibrationCountdown]가 진행 중
  void _updateOverlay({int? score, int? calibrationCountdown}) {
    final mode = _detectedContext;
    final canCalibrate = PostureCalibration.isCalibratableMode(mode);
    final notYetCalibrated = !_calibration.isCalibratedFor(mode);
    final showBtn = canCalibrate &&
        (calibrationCountdown != null || notYetCalibrated);
    final btnText = calibrationCountdown != null
        ? (calibrationCountdown > 0 ? '측정 중 $calibrationCountdown' : '✓ 완료')
        : '🎯 측정';
    OverlayChannel.updateSplit(
      mode: mode,
      risk: _riskState.level,
      score: score,
      showCalibrateBtn: showBtn,
      calibrateBtnText: btnText,
    );
  }

  // ── 네이티브 OverlayService 시작 ──────────────────────────────
  // SYSTEM_ALERT_WINDOW는 사용자가 시스템 설정에서 직접 켜야 하는 특수 권한.
  // 권한 없으면 시작 시도 자체를 스킵 (Kotlin 측에도 방어선이 있지만 여기서 한 번 더).
  Future<void> _setupOverlay() async {
    if (!Platform.isAndroid) return;
    final granted = await Permission.systemAlertWindow.isGranted;
    if (!granted) {
      debugPrint('[Overlay] SYSTEM_ALERT_WINDOW 권한 없음 — 자동 시작 스킵. '
          '프로필 탭의 "오버레이 시작" 버튼을 눌러 권한 허용 후 시작 가능');
      return;
    }
    try {
      await OverlayChannel.start();
      _updateOverlay();
    } catch (e) {
      debugPrint('[Overlay] 오버레이 시작 실패: $e');
    }
  }

  /// 프로필 탭 "오버레이 시작" 버튼 — 권한 없으면 시스템 설정으로 안내.
  Future<void> requestOverlayPermissionAndStart() async {
    if (!Platform.isAndroid) return;
    var granted = await Permission.systemAlertWindow.isGranted;
    if (!granted) {
      // 사용자에게 다이얼로그를 띄움. 거부 시 false 반환되지만 우리는 무시.
      granted = (await Permission.systemAlertWindow.request()).isGranted;
    }
    if (granted) {
      await OverlayChannel.start();
      _updateOverlay();
    }
  }

  Future<void> _captureOnce({bool fromTurtleNeck = false}) async {
    if (!_captureActive) return;
    if (!_useLocalAnalysis && !_connected) return;

    // 결과 처리 시점에 어떤 트리거였는지 알 수 있게 보관.
    // 캡처는 직렬화되어 있어 동시 호출 사이 덮어쓸 위험 없음.
    _currentCaptureFromTurtleNeck = fromTurtleNeck;

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
          // 거북목 트리거로 시작된 캡처일 때만 히스토리 기록.
          // 캘리브레이션 / 수동 시작 캡처는 UI 점수만 갱신.
          if (_currentCaptureFromTurtleNeck) {
            final pitchDeg = (1.0 - (next.scores['pitch'] ?? 1.0)) * 20.0;
            final snap = PostureSnapshot(
              time:     _lastCaptureTime ?? DateTime.now(),
              score:    next.score,
              pitchDeg: pitchDeg,
            );
            _captureHistory.add(snap);
            _snapshots.add(snap);
            _saveHistory();
            debugPrint('[Capture] 거북목 트리거 캡처 — 히스토리 기록 (${next.score}점)');
          } else {
            debugPrint('[Capture] 캘리브레이션/수동 캡처 — 히스토리 제외 (${next.score}점)');
          }
          _currentCaptureFromTurtleNeck = false;
          // 오버레이에 점수 표시 (모든 캡처)
          if (Platform.isAndroid) {
            _updateOverlay(score: next.score);
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
      _headphoneTracker.dispose();
      _contextDetector?.dispose();
      _contextDetector = null;
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
      ProfileTab(
        serverIp: _serverIp,
        onServerIpChanged: _onServerIpChanged,
        onOverlayStart: Platform.isAndroid ? requestOverlayPermissionAndStart : null,
        contextDetector: Platform.isAndroid ? _contextDetector : null,
        cameraSettings:  Platform.isAndroid ? _cameraSettings   : null,
        calibration:     Platform.isAndroid ? _calibration      : null,
        headphoneTracker: Platform.isAndroid ? _headphoneTracker : null,
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
            _navItem(0, Icons.home_rounded,      '홈'),
            _navItem(1, Icons.bar_chart_rounded, '리포트'),
            const SizedBox(width: 56),
            _navItem(3, Icons.person_rounded,    '프로필'),
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
