import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/sensor_posture.dart';

class SensorClassifier {
  static const int    _windowSize       = 40;
  static const int    _cooldownSeconds  = 10; // 첫 촬영 후 10초 뒤 재촬영
  static const int    _sustainedSeconds = 5; // 거북목 지속 필요 시간
  static const String _modelAsset      = 'assets/posture_model.tflite';

  final void Function(SensorPosture)? onPostureChanged;
  final void Function()?              onTurtleNeckDetected;

  Interpreter?             _interpreter;
  final List<List<double>> _window = [];
  List<double>             _lastAcc = [0, 0, 9.8];
  List<double>             _lastGyr = [0, 0, 0];
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>?     _gyrSub;
  DateTime?    _lastTriggerTime;
  Timer?       _turtleNeckTimer;   // 5초 지속 후 트리거 타이머
  Timer?       _graceTimer;        // 짧은 포즈 변화 무시용 (1초 grace)
  SensorPosture _currentPosture = SensorPosture.normal;
  bool          _started        = false;
  bool          _modelLoaded    = false;
  String        _modelError     = '';
  int           _frameCount     = 0;

  SensorClassifier({this.onPostureChanged, this.onTurtleNeckDetected});

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

    if (_window.length == _windowSize) _runInference();
  }

  void _runInference() {
    if (_interpreter == null) {
      // ── TFLite 없음 → 순수 Flutter 임계치 기반 PoC 감지 ──────────
      _runThresholdDetection();
      return;
    }

    try {
      // Float32List로 명시적 변환 (tflite float32 타입 보장)
      final flat = List.generate(
        _windowSize * 8,
        (k) => _window[k ~/ 8][k % 8],
      );

      // 모델 입력 shape 확인 후 맞게 전달
      final inShape = _interpreter!.getInputTensor(0).shape;
      final Object input = inShape.length == 3
          ? [flat.reshape([_windowSize, 8])]   // [1, 40, 8]
          : flat.reshape([_windowSize, 8]);     // [40, 8]

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
      // TFLite 오류 시 임계치 방식으로 대체
      _runThresholdDetection();
    }
  }

  // ── 순수 Flutter PoC: 임계치 기반 거북목 감지 ─────────────────────
  // pitch > 30° (고개 앞으로 숙임) or 최근 40프레임 평균 pitch 기준
  void _runThresholdDetection() {
    // 40 프레임의 pitch 평균
    final avgPitch = _window.map((f) => f[6]).reduce((a, b) => a + b) / _window.length;
    final avgAz    = _window.map((f) => f[2]).reduce((a, b) => a + b) / _window.length;

    // 거북목: pitch 30° 이상 OR Z축 가속도가 크게 낮아짐(앞으로 기울기)
    final isTurtle = avgPitch.abs() > 30 || avgAz < 5.0;

    final posture = isTurtle ? SensorPosture.turtleNeck : SensorPosture.normal;

    debugPrint('[PoC] pitch=${avgPitch.toStringAsFixed(1)}° '
        'az=${avgAz.toStringAsFixed(2)} → ${posture.label}');

    _applyPosture(posture);
  }

  void _applyPosture(SensorPosture posture) {
    if (posture != _currentPosture) {
      _currentPosture = posture;
      onPostureChanged?.call(posture);
    }

    if (posture == SensorPosture.turtleNeck) {
      // 1초 grace timer가 있으면 취소 (flickering 무시)
      _graceTimer?.cancel();
      _graceTimer = null;
      // 5초 타이머가 없으면 새로 시작
      _turtleNeckTimer ??= Timer(
        Duration(seconds: _sustainedSeconds),
        _onSustainedTurtleNeck,
      );
    } else {
      // 거북목 아님: 1초 grace 후 타이머 취소
      // (1초 내로 다시 거북목이 되면 타이머 유지)
      if (_turtleNeckTimer != null && _graceTimer == null) {
        _graceTimer = Timer(const Duration(seconds: 1), () {
          _turtleNeckTimer?.cancel();
          _turtleNeckTimer = null;
          _graceTimer = null;
        });
      }
    }
  }

  void _onSustainedTurtleNeck() {
    _turtleNeckTimer = null;
    final now = DateTime.now();
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!) <
            const Duration(seconds: _cooldownSeconds)) {
      debugPrint('[Sensor] 거북목 지속됨 — 쿨다운 중 (${now.difference(_lastTriggerTime!).inSeconds}s/${_cooldownSeconds}s)');
      return;
    }
    _lastTriggerTime = now;
    debugPrint('[Sensor] 거북목 $_sustainedSeconds초 지속 → 카메라 트리거');
    onTurtleNeckDetected?.call();
  }
}
