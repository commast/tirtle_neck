import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/sensor_posture.dart';
import '../models/detected_context.dart';
import '../models/neck_risk.dart';
import 'posture_calibration.dart';

/// 기기 물리 회전 — 가속도 자체에서 추정한다.
/// portrait: 세로(가로축 ay 가 중력 방향), landscape: 가로(축 ax 가 중력 방향).
enum DeviceOrientation { portrait, landscape }

class SensorClassifier {
  static const int    _windowSize       = 40;
  static const String _modelAsset      = 'assets/posture_model.tflite';
  // 현재 tilt가 baseline에서 이만큼 벗어나면 "자세 바뀜"으로 보고 지속시간 리셋.
  static const double _poseChangeDeg   = 15.0;
  // tilt가 이 값 이상이면 "수직 자세(거의 안전)" — 지속시간 누적 안 함.
  static const double _goodPostureTilt = 60.0;

  // ── 방향 감지(히스테리시스) ────────────────────────────────────────
  // |dominant| / |other| > 비율이면 명확한 방향. 그 사이는 이전 방향 유지.
  static const double _orientRatio          = 1.4;
  // 폰이 거의 평평하면(중력이 z축에 몰리면) 방향 판정 보류.
  static const double _flatGravityRatio     = 0.85;
  // 같은 신규 방향이 N프레임 연속 감지돼야 전환 (약 0.5s @ gameInterval).
  static const int    _orientSwitchFrames   = 10;

  // ── 지속시간 점수 시스템 ──────────────────────────────────────────
  // 누적 임계(초). 비-normal 상태가 dt 만큼 흐르면 +dt, normal 이면 -dt*배수.
  static const double _badScoreThresholdSec = 3.0;
  static const Duration _durationCooldown    = Duration(seconds: 45);
  static const double _recoveryMultiplier    = 2.0;
  // dt가 이 값보다 크면(앱 백그라운드 지연 등) 점수 업데이트 스킵.
  static const double _maxDtSec              = 5.0;

  DetectedContext _currentContext = DetectedContext.normal;

  final void Function(SensorPosture)?  onPostureChanged;
  final void Function(NeckRiskState)?  onRiskChanged;
  /// 지속시간 점수가 임계를 넘었을 때 1회 호출 (쿨다운 후 다시 가능).
  final void Function()?               onDurationAlert;

  /// 개인 baseline tilt. null이면 절대 각도 기반 기본 채점.
  PostureCalibration? calibration;

  Interpreter?             _interpreter;
  final List<List<double>> _window = [];
  List<double>             _lastAcc = [0, 0, 9.8];
  List<double>             _lastGyr = [0, 0, 0];
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>?     _gyrSub;
  SensorPosture _currentPosture = SensorPosture.normal;
  NeckRiskLevel _currentRiskLevel = NeckRiskLevel.normal;
  DateTime?     _poseStartTime;       // 같은 자세 지속 시작 시각
  double?       _baselineTiltDeg;     // 자세 기준 (EMA로 천천히 추종)
  DateTime?     _stillStartTime;      // 자이로 거의 0 유지 시작 시각
  bool          _started        = false;
  bool          _modelLoaded    = false;
  String        _modelError     = '';
  int           _frameCount     = 0;

  // ── 방향 감지 상태 ──────────────────────────────────────────────
  DeviceOrientation _orientation        = DeviceOrientation.portrait;
  DeviceOrientation _pendingOrientation = DeviceOrientation.portrait;
  int               _orientationStreak  = 0;

  // ── 지속시간 점수 상태 ──────────────────────────────────────────
  double    _badScoreSec        = 0.0;
  DateTime? _lastDurationAlertAt;
  DateTime? _lastScoreUpdate;

  SensorClassifier({
    this.onPostureChanged,
    this.onRiskChanged,
    this.onDurationAlert,
    this.calibration,
  });

  DeviceOrientation get currentOrientation => _orientation;

  void updateContext(DetectedContext ctx) {
    if (_currentContext == ctx) return;
    _currentContext = ctx;
    debugPrint('[Sensor] 컨텍스트 → ${ctx.label}  (pitch임계=${ctx.pitchThreshold}°)');
    // 컨텍스트 전환 시 지속시간 점수도 초기화 — 이전 컨텍스트 누적이 새 모드로 새지 않게.
    _badScoreSec = 0.0;
    _lastScoreUpdate = null;
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
    // 알람 발사는 지속시간 점수 시스템(_updateDurationScore → onDurationAlert) 이 담당.
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
    // 1) 방향 추정 + 히스테리시스 적용
    _updateOrientation(e.x, e.y, e.z);
    // 2) 현재 방향에 맞춰 portrait 기준 좌표계로 리매핑해서 저장
    _lastAcc = _remapForOrientation(e.x, e.y, e.z);
    _processFrame();
  }

  void _onGyr(GyroscopeEvent e) {
    // 자이로도 동일한 변환을 적용해 분산 계산이 일관되게.
    _lastGyr = _remapForOrientation(e.x, e.y, e.z);
  }

  /// 가속도 크기로 현재 폰의 물리 방향을 추정한다.
  /// - 폰이 거의 평평하면(중력이 az에 몰림) 이전 방향 유지
  /// - |ay|/|ax| 비율로 portrait/landscape 판정
  /// - 신규 방향이 _orientSwitchFrames 연속 잡혀야 실제 전환 (지터 방지)
  void _updateOrientation(double ax, double ay, double az) {
    final g = sqrt(ax * ax + ay * ay + az * az);
    if (g < 4.0) return; // 거의 자유낙하/이상치
    if (az.abs() / g > _flatGravityRatio) return; // 평평하게 누움 — 판정 보류

    final absX = ax.abs();
    final absY = ay.abs();
    DeviceOrientation? detected;
    if (absY > absX * _orientRatio) {
      detected = DeviceOrientation.portrait;
    } else if (absX > absY * _orientRatio) {
      detected = DeviceOrientation.landscape;
    }
    if (detected == null) return; // 비율 경계 — 이전 유지

    if (detected == _orientation) {
      _pendingOrientation = detected;
      _orientationStreak = 0;
      return;
    }
    if (detected == _pendingOrientation) {
      _orientationStreak++;
    } else {
      _pendingOrientation = detected;
      _orientationStreak = 1;
    }
    if (_orientationStreak >= _orientSwitchFrames) {
      debugPrint('[Sensor] 방향 전환: ${_orientation.name} → ${detected.name}');
      _orientation = detected;
      _orientationStreak = 0;
      // 방향 전환은 자세 자체가 크게 바뀌는 순간이므로 지속시간 점수도 리셋
      _badScoreSec = 0.0;
      _lastScoreUpdate = null;
    }
  }

  /// 현재 방향에 맞춰 디바이스 축 → portrait 기준 축으로 변환.
  /// landscape 에선 (x, y) 자리를 (y, -x) 로 swap (시계 반대방향 90° 회전 보상).
  /// 디바이스 좌표계 차이로 부호가 반대이면 이 함수 한 줄만 수정.
  List<double> _remapForOrientation(double x, double y, double z) {
    if (_orientation == DeviceOrientation.landscape) {
      return [y, -x, z];
    }
    return [x, y, z];
  }

  /// 지속시간 점수 업데이트 — 비-normal 이면 +dt, normal 이면 -dt*배수.
  /// 임계 도달 시 쿨다운 통과하면 onDurationAlert 1회 발사하고 점수 리셋.
  void _updateDurationScore(NeckRiskLevel level, DateTime now) {
    final prev = _lastScoreUpdate;
    _lastScoreUpdate = now;
    if (prev == null) return;
    final dt = now.difference(prev).inMilliseconds / 1000.0;
    if (dt <= 0 || dt > _maxDtSec) return;

    if (level != NeckRiskLevel.normal) {
      _badScoreSec += dt;
    } else {
      _badScoreSec =
          (_badScoreSec - dt * _recoveryMultiplier).clamp(0.0, _badScoreThresholdSec * 2);
    }

    if (_badScoreSec >= _badScoreThresholdSec) {
      final last = _lastDurationAlertAt;
      if (last == null || now.difference(last) >= _durationCooldown) {
        _lastDurationAlertAt = now;
        _badScoreSec = 0.0;
        debugPrint('[Risk] 지속시간 누적 임계 도달 → onDurationAlert 발사');
        onDurationAlert?.call();
      }
    }
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
        final st = _computeRisk();
        _applyRisk(st);
        // 지속시간 점수: 비-normal 누적 → 임계 + 쿨다운 통과 시 알람 콜백.
        _updateDurationScore(st.level, DateTime.now());
      }
    }
  }

  void _runInference() {
    if (!_currentContext.isMonitoringActive) {
      // 운동 중 또는 수면 중 — 감지 중지
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
