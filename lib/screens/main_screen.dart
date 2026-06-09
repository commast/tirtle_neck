import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants.dart';
import '../models/detected_context.dart';
import '../models/neck_risk.dart';
import '../services/sensor_classifier.dart';
import '../services/context_detector.dart';
import '../services/overlay_channel.dart';
import '../services/posture_calibration.dart';
import '../services/background_calibration_runner.dart';
import '../services/usage_tracker_service.dart';
import '../services/alert_settings.dart';
import 'home_tab.dart';
import 'report_tab.dart';
import 'profile_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _tabIndex = 0;
  late AnimationController _warnAnim;

  // 알람 정책:
  // - 주의(caution): SensorClassifier 의 지속시간 점수 + 45s 쿨다운이 게이트.
  // - 경고(risk): AlertSettings.riskWindowMinutes 슬라이딩 윈도우에
  //   AlertSettings.riskCautionCount 회 누적 시 발사,
  //   쿨다운은 AlertSettings.riskCooldownMinutes (1~60분, 기본 15분).
  DateTime? _nextRiskAt;
  final List<DateTime> _cautionTimestamps = [];

  // ── 센서 자세 분류기 + 컨텍스트 감지 (Android 전용) ──────────────
  SensorClassifier? _sensorClassifier;
  ContextDetector?  _contextDetector;
  VoidCallback?     _ctxListener;
  VoidCallback?     _snapListener;
  DetectedContext   _detectedContext = DetectedContext.normal;
  NeckRiskState     _riskState       = NeckRiskState.initial;
  final PostureCalibration          _calibration = PostureCalibration();
  final BackgroundCalibrationRunner _calRunner   = BackgroundCalibrationRunner();
  bool _calibrationInProgress = false;

  // 센서 모니터링 활성화 여부 (FAB 토글).
  bool _sensorActive = false;
  bool _sensorBusy   = false;

  /// 외부(ProfileTab 등) 에서 컨텍스트 상태를 구독할 수 있게 노출.
  ContextDetector?   get contextDetector => _contextDetector;
  PostureCalibration get calibration     => _calibration;
  NeckRiskState      get riskState       => _riskState;

  @override
  void initState() {
    super.initState();
    _warnAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _initForegroundTask();

    if (Platform.isAndroid) {
      _contextDetector = ContextDetector();
      AlertSettings.instance.load();
      _calibration.load();
      OverlayChannel.setCalibrateTappedHandler(_handleOverlayCalibrateTapped);
      Future.microtask(() async {
        // READ_PHONE_STATE 권한 미리 요청 (통화 중 감지용).
        await Permission.phone.request();
        // PACKAGE_USAGE_STATS는 보호된 권한 — 사용자가 ProfileTab에서 직접 설정 화면을 열어 허용해야 함.
        await _contextDetector!.start();
        await UsageTrackerService.instance.init(_contextDetector!);
        _ctxListener = () {
          try {
            final det = _contextDetector;
            if (det == null) return;
            final ctx = det.context.value;
            _sensorClassifier?.updateContext(ctx);
            if (!mounted) return;
            setState(() => _detectedContext = ctx);
            _updateOverlay();
          } catch (e) {
            debugPrint('[CtxListener] 예외 — 무시: $e');
          }
        };
        _contextDetector!.context.addListener(_ctxListener!);
        // 같은 컨텍스트 안에서 앱 이름이 바뀌어도 오버레이 라벨 갱신 (예: 유튜브 → 트위치).
        _snapListener = () {
          try {
            if (!mounted) return;
            _updateOverlay();
          } catch (e) {
            debugPrint('[SnapListener] 예외 — 무시: $e');
          }
        };
        _contextDetector!.snapshot.addListener(_snapListener!);
        // 첫 프레임 그려진 뒤 권한 누락 알림.
        WidgetsBinding.instance.addPostFrameCallback((_) => _promptMissingPermissions());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid) _setupOverlay();
    }
  }

  // ── 포그라운드 서비스 (센서 백그라운드 유지용) ──────────────────
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
        // 서비스 유지용 이벤트 (2분 간격).
        eventAction: ForegroundTaskEventAction.repeat(120000),
        autoRunOnBoot:  false,
        allowWifiLock:  true,
      ),
    );
  }

  Future<void> _startSensorForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId:         256,
      notificationTitle: '포스처가드',
      notificationText:  '자세를 감지하고 있습니다.',
      callback:          _postureTaskCallback,
    );
  }

  /// 센서 모니터링 시작 — SensorClassifier 생성 + 포그라운드 서비스 + 오버레이.
  Future<void> _startSensorMonitoring() async {
    if (!Platform.isAndroid) return;
    _sensorClassifier ??= SensorClassifier(
      onPostureChanged: (p) {
        _contextDetector?.updateSensorPosture(p);
      },
      onRiskChanged: (risk) {
        if (mounted) setState(() => _riskState = risk);
        // UI/오버레이만 즉시 반영. 실제 알람 발사는 지속시간 점수가 임계를
        // 넘었을 때(onDurationAlert) 1회만 수행 — 손떨림/짧은 흐트러짐 오탐 차단.
        _updateOverlay();
      },
      // 지속시간 점수가 10초 누적 + 45s 쿨다운 통과 시 1회 호출.
      // _fireAlertIfDue 내부의 3-cautions-in-30min 에스컬레이션 + 빨간 배너 로직은 유지.
      // 알람 게이트는 _shouldFireAlarm — 통화 중만 차단, 그 외(영상/게임/SNS/학습/책상/일반)
      // 에서는 모두 울려서 사용자가 어떤 상황에서도 자세 경고를 받을 수 있게.
      onDurationAlert: () {
        if (!_shouldFireAlarm) return;
        _fireAlertIfDue(NeckRiskLevel.caution);
      },
      calibration: _calibration,
    );
    // 현재 컨텍스트를 분류기에 주입 (모드별 임계값 적용)
    final ctx = _contextDetector?.context.value;
    if (ctx != null) _sensorClassifier!.updateContext(ctx);
    await _sensorClassifier!.start();
    await _startSensorForegroundService();
    await _setupOverlay();
  }

  /// 센서 모니터링 종료 — 구독 해제 + 포그라운드 서비스 중지.
  Future<void> _stopSensorMonitoring() async {
    if (!Platform.isAndroid) return;
    _sensorClassifier?.dispose();
    _sensorClassifier = null;
    _cancelAlertCycle();
    _cautionTimestamps.clear(); // FAB OFF 시에만 누적 카운터 완전 초기화
    _overlayVisible = false;
    setState(() => _riskState = NeckRiskState.initial);
    try { await FlutterForegroundTask.stopService(); } catch (_) {}
    try { await OverlayChannel.stop(); } catch (_) {}
  }

  /// 지속시간 점수 임계 통과 시 호출.
  /// 사용량 트래커에는 항상 기록·타임스탬프 누적. 알람은
  /// - 일반 케이스: 주의 알람 (진동·소리 1회)
  /// - 30분 윈도우에 3회 누적 + 경고 쿨다운 통과: 주의 알람 생략하고 경고만 발사 + 빨간 배너
  void _fireAlertIfDue(NeckRiskLevel _) {
    final now = DateTime.now();

    // 사용량 트래커 기록 + 타임스탬프 누적
    UsageTrackerService.instance.recordWarning();
    _cautionTimestamps.add(now);

    // 윈도우 밖 항목 정리
    final cutoff = now.subtract(
      const Duration(minutes: AlertSettings.riskWindowMinutes),
    );
    _cautionTimestamps.removeWhere((t) => t.isBefore(cutoff));

    // 경고 에스컬레이션 조건: 윈도우 내 누적 횟수 + 경고 쿨다운 지남
    final riskDue = _nextRiskAt == null || now.isAfter(_nextRiskAt!);
    final escalate =
        _cautionTimestamps.length >= AlertSettings.riskCautionCount && riskDue;

    if (escalate) {
      // 경고만 발사 (주의 알람은 생략 — 텀 없이 두 번 울리는 것 방지)
      AlertSettings.instance.triggerAlert(NeckRiskLevel.risk);
      UsageTrackerService.instance.recordRisk();
      _nextRiskAt = now.add(
        Duration(minutes: AlertSettings.instance.riskCooldownMinutes),
      );
      _showRiskBanner();
    } else {
      // 평상시: 주의 알람만 발사
      AlertSettings.instance.triggerAlert(NeckRiskLevel.caution);
    }
  }

  /// 30분 내 주의 3회 누적 → 화면 상단에 빨간 경고 배너.
  void _showRiskBanner() {
    try {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFD32F2F),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '경고 — 자세가 계속 나쁩니다. 잠깐 스트레칭 하세요!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
        ),
      );
    } catch (e) {
      debugPrint('[RiskBanner] 표시 실패 — 무시: $e');
    }
  }

  void _cancelAlertCycle() {
    _nextRiskAt = null;
    // _cautionTimestamps 는 여기서 초기화하지 않음 — 컨텍스트 이탈로 리셋되면 안 됨.
    // 완전 초기화는 _stopSensorMonitoring(FAB OFF) 에서만 수행.
  }

  Future<void> _toggleSensor() async {
    if (_sensorBusy) return;
    setState(() => _sensorBusy = true);
    try {
      if (_sensorActive) {
        await _stopSensorMonitoring();
        setState(() => _sensorActive = false);
      } else {
        await _startSensorMonitoring();
        setState(() => _sensorActive = true);
      }
    } finally {
      if (mounted) setState(() => _sensorBusy = false);
    }
  }

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
      _updateOverlay(calibrationCountdown: remaining);
    });
    if (result != null) {
      await _calibration.saveFor(mode, result);
      debugPrint('[Cal] ${mode.label} baseline 저장: '
          '${result.toStringAsFixed(1)}°');
    }
    if (mounted) setState(() => _calibrationInProgress = false);
    _updateOverlay();
  }

  /// 오버레이 칩을 보여줘야 하는 컨텍스트(영상/게임/SNS/학습) 인지 여부.
  bool get _shouldShowOverlay {
    final m = _detectedContext;
    return m == DetectedContext.watchingVideo ||
           m == DetectedContext.gaming ||
           m == DetectedContext.social ||
           m == DetectedContext.studying;
  }

  /// 진동·소리 알람을 울릴지 여부.
  /// 백그라운드에서 영상/게임/SNS/학습 앱 실행 시에만 허용 — 대기/책상/일반 등에선 차단.
  bool get _shouldFireAlarm => _shouldShowOverlay;

  bool _overlayVisible = false;

  void _updateOverlay({int? score, int? calibrationCountdown}) {
    if (!_shouldShowOverlay) {
      if (_overlayVisible) {
        OverlayChannel.stop();
        _overlayVisible = false;
      }
      _cancelAlertCycle();
      return;
    }
    final mode = _detectedContext;
    final canCalibrate = PostureCalibration.isCalibratableMode(mode);
    final notYetCalibrated = !_calibration.isCalibratedFor(mode);
    final showBtn = canCalibrate &&
        (calibrationCountdown != null || notYetCalibrated);
    final btnText = calibrationCountdown != null
        ? (calibrationCountdown > 0 ? '측정 중 $calibrationCountdown' : '✓ 완료')
        : '🎯 측정';
    final displayRisk = _riskState.level;
    if (!_overlayVisible) {
      OverlayChannel.start();
      _overlayVisible = true;
    }
    OverlayChannel.updateSplit(
      mode: mode,
      risk: displayRisk,
      score: score,
      showCalibrateBtn: showBtn,
      calibrateBtnText: btnText,
    );
  }

  // ── 네이티브 OverlayService 시작 ──────────────────────────────
  Future<void> _setupOverlay() async {
    if (!Platform.isAndroid) return;
    final granted = await Permission.systemAlertWindow.isGranted;
    if (!granted) {
      debugPrint('[Overlay] SYSTEM_ALERT_WINDOW 권한 없음 — 자동 시작 스킵.');
      return;
    }
    try {
      await OverlayChannel.start();
      _updateOverlay();
    } catch (e) {
      debugPrint('[Overlay] 오버레이 시작 실패: $e');
    }
  }

  /// 앱 시작 직후 호출 — PACKAGE_USAGE_STATS / SYSTEM_ALERT_WINDOW 누락 시 안내.
  Future<void> _promptMissingPermissions() async {
    if (!mounted || !Platform.isAndroid) return;
    final usageGranted =
        await _contextDetector?.foregroundAppChannel.hasPermission() ?? true;
    final overlayGranted = await Permission.systemAlertWindow.isGranted;
    final missing = <String>[];
    if (!usageGranted) missing.add('· 앱 사용 정보 접근 (포그라운드 앱 감지)');
    if (!overlayGranted) missing.add('· 다른 앱 위에 표시 (오버레이)');
    if (missing.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('권한 설정이 필요해요'),
        content: Text(
          '다음 권한이 꺼져 있어 정상 동작하지 않습니다:\n\n'
          '${missing.join('\n')}\n\n'
          '설정에서 허용해주세요.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('나중에'),
          ),
          if (!usageGranted)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _contextDetector?.foregroundAppChannel.openSettings();
              },
              child: const Text('사용 정보 설정'),
            ),
          if (!overlayGranted)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await Permission.systemAlertWindow.request();
              },
              child: const Text('오버레이 허용'),
            ),
        ],
      ),
    );
  }

  Future<void> requestOverlayPermissionAndStart() async {
    if (!Platform.isAndroid) return;
    var granted = await Permission.systemAlertWindow.isGranted;
    if (!granted) {
      granted = (await Permission.systemAlertWindow.request()).isGranted;
    }
    if (granted) {
      await OverlayChannel.start();
      _updateOverlay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _warnAnim.dispose();
    if (Platform.isAndroid) {
      // 리스너는 detector dispose 전에 분리.
      final det = _contextDetector;
      if (det != null) {
        if (_ctxListener != null) det.context.removeListener(_ctxListener!);
        if (_snapListener != null) det.snapshot.removeListener(_snapListener!);
      }
      _ctxListener = null;
      _snapListener = null;
      _contextDetector?.dispose();
      _contextDetector = null;
      _sensorClassifier?.dispose();
      FlutterForegroundTask.stopService();
      OverlayChannel.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeTab(),
      const ReportTab(),
      ProfileTab(
        onOverlayStart: Platform.isAndroid ? requestOverlayPermissionAndStart : null,
        calibration:    Platform.isAndroid ? _calibration : null,
      ),
    ];

    return Scaffold(
      backgroundColor: kBg,
      body: screens[_tabIndex],
      floatingActionButton: FloatingActionButton(
        backgroundColor: _sensorActive ? Colors.red : kGreen,
        elevation: 4,
        shape: const CircleBorder(),
        onPressed: _sensorBusy ? null : _toggleSensor,
        child: _sensorBusy
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white,
                ),
              )
            : Icon(
                _sensorActive ? Icons.sensors_off_rounded : Icons.sensors_rounded,
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
            Transform.translate(
              offset: const Offset(-16, 0),
              child: _navItem(2, Icons.person_rounded, '프로필'),
            ),
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
// @pragma 필수: 별도 isolate 에서 실행되므로 트리 쉐이킹 방지.
@pragma('vm:entry-point')
void _postureTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_PostureTaskHandler());
}

class _PostureTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {}
}
