import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/sensor_posture.dart';
import '../models/detected_context.dart';
import '../models/neck_risk.dart';
import 'posture_calibration.dart';

class SensorClassifier {
  static const int    _windowSize       = 40;
  static const int    _cooldownSeconds  = 10;
  static const int    _sustainedSeconds = 5; // risk 레벨이 5초 유지되면 트리거
  static const String _modelAsset      = 'assets/posture_model.tflite';
  // 현재 tilt가 baseline에서 이만큼 벗어나면 "자세 바뀜"으로 보고 지속시간 리셋.
  static const double _poseChangeDeg   = 15.0;
  // tilt가 이 값 이상이면 "수직 자세(거의 안전)" — 지속시간 누적 안 함.
  static const double _goodPostureTilt = 60.0;

  DetectedContext _currentContext = DetectedContext.normal;

  final void Function(SensorPosture)?  onPostureChanged;
  final void Function(NeckRiskState)?  onRiskChanged;
  final void Function()?               onTurtleNeckDetected;

  /// 개인 baseline tilt. null이면 절대 각도 기반 기본 채점.
  PostureCalibration? calibration;

  Interpreter?             _interpreter;
  final List<List<double>> _window = [];
  List<double>             _lastAcc = [0, 0, 9.8];
  List<double>             _lastGyr = [0, 0, 0];
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>?     _gyrSub;
  DateTime?    _lastTriggerTime;
  Timer?       _turtleNeckTimer;
  Timer?       _graceTimer;
  SensorPosture _currentPosture = SensorPosture.normal;
  NeckRiskLevel _currentRiskLevel = NeckRiskLevel.normal;
  DateTime?     _poseStartTime;       // 같은 자세 지속 시작 시각
  double?       _baselineTiltDeg;     // 자세 기준 (EMA로 천천히 추종)
  DateTime?     _stillStartTime;      // 자이로 거의 0 유지 시작 시각
  bool          _started        = false;
  bool          _modelLoaded    = false;
  String        _modelError     = '';
  int           _frameCount     = 0;

  SensorClassifier({
    this.onPostureChanged,
    this.onRiskChanged,
    this.onTurtleNeckDetected,
    this.calibration,
  });

  void updateContext(DetectedContext ctx) {
    if (_currentContext == ctx) return;
    _currentContext = ctx;
    debugPrint('[Sensor] 컨텍스트 → ${ctx.label}  (pitch임계=${ctx.pitchThreshold}°)');
    // 컨텍스트 전환 시 항상 타이머 리셋: 이전 임계로 시작된 카운트가
    // 새 임계 컨텍스트로 넘어가 자세 전환 도중 오발동하는 것 방지.
    _cancelTurtleNeckTimers();
  }

  void _cancelTurtleNeckTimers() {
    _turtleNeckTimer?.cancel();
    _turtleNeckTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  /// IMU 센서 기반 거북목 위험도 계산.
  /// 사용자 보고 기반 조정 알고리즘:
  ///  - pitch (0~40): 기울기. 60° 이상=거의 수직=안전.
  ///  - gyro (0~20): 자세 고정도. 작은 흔들림에 관대.
  ///  - duration (0~40): 같은 자세 지속시간. 단, 좋은 자세(>60°)에선 누적 안 함.
  ///  - 자세 변경 감지: gyro가 아니라 tilt가 baseline에서 ±15° 벗어나면 리셋.
  NeckRiskState _computeRisk() {
    if (_window.length < _windowSize) return NeckRiskState.initial;

    // ── 1) 폰 기울기 (수평 0° ~ 수직 90°) ──
    final ax = _window.map((f) => f[0]).reduce((a, b) => a + b) / _window.length;
    final ay = _window.map((f) => f[1]).reduce((a, b) => a + b) / _window.length;
    final az = _window.map((f) => f[2]).reduce((a, b) => a + b) / _window.length;
    final tiltDeg = atan2(ay.abs(), sqrt(ax * ax + az * az)) * 180 / pi;

    // ── pitch 점수: baseline이 있으면 편차 기반, 없으면 절대 각도 기반 ──
    final int pitchScore;
    final baseline = calibration?.baselineFor(_currentContext);
    if (baseline != null) {
      // 편차 = baseline 보다 얼마나 더 수평으로 기울었는가 (양수일 때만 위험)
      final deviation = (baseline - tiltDeg).clamp(0.0, 90.0);
      pitchScore = deviation > 30
          ? 40 // baseline 대비 30°+ 숙임 — 매우 위험
          : deviation > 20
              ? 30
              : deviation > 12
                  ? 18
                  : deviation > 6
                      ? 8
                      : 2; // 거의 평소 자세 — 안전
    } else {
      pitchScore = tiltDeg < 20
          ? 40
          : tiltDeg < 40
              ? 30
              : tiltDeg < 60
                  ? 18
                  : tiltDeg < 75
                      ? 8
                      : 2;
    }

    // ── 2) 자이로 분산 — 자세 고정도 (관대하게) ──
    final gMags = _window
        .map((f) => sqrt(f[3] * f[3] + f[4] * f[4] + f[5] * f[5]))
        .toList();
    final gMean = gMags.reduce((a, b) => a + b) / gMags.length;
    final gVar = gMags
            .map((g) => (g - gMean) * (g - gMean))
            .reduce((a, b) => a + b) /
        gMags.length;

    final gyroScore = gVar < 0.05
        ? 20 // 거의 정지 — 자세 고정
        : gVar < 0.5
            ? 10 // 약한 움직임 (손떨림 정도)
            : 3; // 활발한 움직임 — 일시적

    // ── 3) 같은 자세 지속 시간 (tilt 기반 추적) ──
    final now = DateTime.now();
    if (_baselineTiltDeg == null) {
      _baselineTiltDeg = tiltDeg;
      _poseStartTime = now;
    } else if ((tiltDeg - _baselineTiltDeg!).abs() > _poseChangeDeg) {
      // 자세가 크게 바뀜 — 리셋 후 새 baseline
      _baselineTiltDeg = tiltDeg;
      _poseStartTime = now;
    } else {
      // 유지 중 — baseline을 EMA로 천천히 갱신
      _baselineTiltDeg = _baselineTiltDeg! * 0.99 + tiltDeg * 0.01;
    }
    final sustainedSec = now.difference(_poseStartTime ?? now).inSeconds;

    // 좋은 자세에선 지속시간 점수 최소.
    // baseline 있으면 baseline ±6° 안이면 좋은 자세, 없으면 절대 60° 이상.
    final isGoodPose = baseline != null
        ? (tiltDeg - baseline).abs() < 6.0
        : tiltDeg > _goodPostureTilt;
    final int durationScore;
    if (isGoodPose) {
      durationScore = 3;
    } else {
      durationScore = sustainedSec > 600
          ? 40 // 10분+
          : sustainedSec > 180
              ? 30 // 3~10분
              : sustainedSec > 60
                  ? 20 // 1~3분
                  : sustainedSec > 30
                      ? 12 // 30s~1분
                      : 3;
    }

    // ── 4) 정지 지속 (게임/영상 모드 한정 보너스) ──
    // 자이로 분산 0.02 미만 = 거의 안 움직임 (스크롤·터치도 안 함).
    // 이상 = 리셋. 게임/영상 외 모드에선 보너스 적용 안 함.
    if (gVar < 0.02) {
      _stillStartTime ??= now;
    } else {
      _stillStartTime = null;
    }
    final stillSec = _stillStartTime != null
        ? now.difference(_stillStartTime!).inSeconds
        : 0;

    final isFocusMode = _currentContext == DetectedContext.gaming ||
                        _currentContext == DetectedContext.watchingVideo;
    int stillnessBonus = 0;
    if (isFocusMode) {
      if (stillSec > 300) {
        stillnessBonus = 40; // 5분+
      } else if (stillSec > 180) {
        stillnessBonus = 28; // 3~5분
      } else if (stillSec > 60) {
        stillnessBonus = 15; // 1~3분
      }
    }

    // ── 5) 모드 가중치 적용 ──
    final raw = pitchScore + gyroScore + durationScore + stillnessBonus; // 0~140
    final weight = _currentContext.riskWeight;
    final score = (raw * weight).round().clamp(0, 100);
    final level = NeckRiskLevelExt.fromScore(score);

    return NeckRiskState(
      level: level,
      score: score,
      rawScore: raw,
      pitchScore: pitchScore,
      gyroScore: gyroScore,
      durationScore: durationScore,
      stillnessBonus: stillnessBonus,
      tiltDeg: tiltDeg,
      gyroVariance: gVar,
      sustainedSec: sustainedSec,
      stillSec: stillSec,
      modeWeight: weight,
    );
  }

  void _applyRisk(NeckRiskState st) {
    if (st.level != _currentRiskLevel) {
      _currentRiskLevel = st.level;
      debugPrint('[Risk] ${st.level.label} '
          '점수=${st.score} (pitch=${st.pitchScore}, gyro=${st.gyroScore}, '
          'dur=${st.durationScore}, still보너스=${st.stillnessBonus}, '
          'tilt=${st.tiltDeg.toStringAsFixed(1)}°, '
          'gVar=${st.gyroVariance.toStringAsFixed(3)}, '
          '자세지속=${st.sustainedSec}s, 정지지속=${st.stillSec}s, '
          'w=${st.modeWeight})');
    }
    onRiskChanged?.call(st);

    // 위험 단계가 5초 유지되면 카메라 트리거 후보로 발사.
    // 실제 카메라 발사 여부는 main_screen에서 컨텍스트 + 사용자 설정으로 게이팅.
    if (st.level == NeckRiskLevel.risk) {
      _graceTimer?.cancel();
      _graceTimer = null;
      _turtleNeckTimer ??= Timer(
        Duration(seconds: _sustainedSeconds),
        _onSustainedRisk,
      );
    } else {
      if (_turtleNeckTimer != null && _graceTimer == null) {
        _graceTimer = Timer(const Duration(seconds: 1), () {
          _turtleNeckTimer?.cancel();
          _turtleNeckTimer = null;
          _graceTimer = null;
        });
      }
    }
  }

  void _onSustainedRisk() {
    _turtleNeckTimer = null;
    final now = DateTime.now();
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!) <
            const Duration(seconds: _cooldownSeconds)) {
      return;
    }
    _lastTriggerTime = now;
    debugPrint('[Risk] 위험 $_sustainedSeconds초 지속 → 카메라 후보 트리거');
    onTurtleNeckDetected?.call();
  }

  SensorPosture get currentPosture => _currentPosture;
  bool          get isModelLoaded  => _modelLoaded;
  String        get modelError     => _modelError;
  int           get windowFill     => _window.length; // 디버그용

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _loadModel();
      _accSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onAcc,
          onError: (e) => debugPrint('[Sensor] 가속도계 오류: $e'),
          cancelOnError: false);
      _gyrSub = gyroscopeEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_onGyr,
          onError: (e) => debugPrint('[Sensor] 자이로 오류: $e'),
          cancelOnError: false);
      debugPrint('[Sensor] 시작됨 (모델로드=$_modelLoaded)');
    } catch (e) {
      _modelError = e.toString();
      debugPrint('[Sensor] 초기화 실패: $e');
      _started = false;
    }
  }

  void stop() {
    _accSub?.cancel();
    _gyrSub?.cancel();
    _accSub = null;
    _gyrSub = null;
    _turtleNeckTimer?.cancel();
    _turtleNeckTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    _started = false;
  }

  void dispose() {
    stop();
    _interpreter?.close();
    _interpreter = null;
    _modelLoaded = false;
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);
      final inShape  = _interpreter!.getInputTensor(0).shape;
      final outShape = _interpreter!.getOutputTensor(0).shape;
      _modelLoaded = true;
      debugPrint('[Sensor] 모델 로드 완료  입력=$inShape  출력=$outShape');
    } catch (e) {
      _modelLoaded = false;
      _modelError = '모델 로드 실패: $e';
      debugPrint('[Sensor] $_modelError');
    }
  }

  void _onAcc(AccelerometerEvent e) {
    _lastAcc = [e.x, e.y, e.z];
    _processFrame();
  }

  void _onGyr(GyroscopeEvent e) {
    _lastGyr = [e.x, e.y, e.z];
  }

  void _processFrame() {
    _frameCount++;
    final ax = _lastAcc[0], ay = _lastAcc[1], az = _lastAcc[2];
    final pitch = atan2(-ax, sqrt(ay * ay + az * az)) * (180 / pi);
    final roll  = atan2( ay,  az)                     * (180 / pi);

    _window.add([ax, ay, az, _lastGyr[0], _lastGyr[1], _lastGyr[2], pitch, roll]);
    if (_window.length > _windowSize) _window.removeAt(0);

    // 윈도우 채움 상태 로그 (첫 50프레임)
    if (_frameCount <= 50) {
      debugPrint('[Sensor] 프레임 $_frameCount / 윈도우 ${_window.length}/$_windowSize '
          'acc=(${ax.toStringAsFixed(1)},${ay.toStringAsFixed(1)},${az.toStringAsFixed(1)})');
    }

    if (_window.length == _windowSize) {
      _runInference();
      // 자세 분류와 별개로, 매 프레임 위험도 계산 (IMU 기반 3단계).
      // 컨텍스트가 운동/수면이면 감지 비활성이므로 스킵.
      if (_currentContext.isMonitoringActive) {
        _applyRisk(_computeRisk());
      }
    }
  }

  void _runInference() {
    if (!_currentContext.isMonitoringActive) {
      // 운동 중 또는 수면 중 — 감지 중지
      _cancelTurtleNeckTimers();
      return;
    }

    if (_interpreter == null) {
      _runThresholdDetection();
      return;
    }

    try {
      final flat = List.generate(
        _windowSize * 8,
        (k) => _window[k ~/ 8][k % 8],
      );

      final inShape = _interpreter!.getInputTensor(0).shape;
      final Object input = inShape.length == 3
          ? [flat.reshape([_windowSize, 8])]
          : flat.reshape([_windowSize, 8]);

      final output = [List<double>.filled(5, 0.0)];
      _interpreter!.run(input, output);

      final probs    = output[0];
      final maxIndex = probs.indexOf(probs.reduce(max));
      final posture  = SensorPostureExt.fromIndex(maxIndex);

      debugPrint('[TFLite] ${posture.label}  '
          'N=${probs[0].toStringAsFixed(3)} '
          'T=${probs[1].toStringAsFixed(3)} '
          'D=${probs[2].toStringAsFixed(3)} '
          'SL=${probs[3].toStringAsFixed(3)} '
          'L=${probs[4].toStringAsFixed(3)}');

      _applyPosture(posture);
    } catch (e, st) {
      debugPrint('[TFLite] 추론 오류: $e\n$st');
      _runThresholdDetection();
    }
  }

  // ── 순수 Flutter PoC: 임계치 기반 거북목 감지 ─────────────────────
  // 컨텍스트에 따라 pitch 임계값이 동적으로 조정됨 (영상/게임/소셜/책상 22°, 학습 25°, 일반 30°)
  void _runThresholdDetection() {
    final avgPitch = _window.map((f) => f[6]).reduce((a, b) => a + b) / _window.length;

    final threshold = _currentContext.pitchThreshold;
    final isTurtle  = avgPitch.abs() > threshold;

    final posture = isTurtle ? SensorPosture.turtleNeck : SensorPosture.normal;

    debugPrint('[PoC] pitch=${avgPitch.toStringAsFixed(1)}° '
        '임계=${threshold.toStringAsFixed(0)}° → ${posture.label}');

    _applyPosture(posture);
  }

  /// 자세 분류 결과를 컨텍스트 디텍터에 전달만 한다.
  /// 카메라 트리거는 더 이상 자세가 아닌 위험도(`_applyRisk`)가 담당.
  void _applyPosture(SensorPosture posture) {
    if (posture != _currentPosture) {
      _currentPosture = posture;
      onPostureChanged?.call(posture);
    }
  }
}
