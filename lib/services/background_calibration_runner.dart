import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// 5초간 가속도계를 직접 구독해 평균 tilt 를 측정.
/// 다이얼로그 없이 백그라운드에서 실행 — 오버레이 측정 버튼이 이걸 호출.
///
/// 진행 상황은 [onTick] 콜백으로 매초 알림 (남은 초). 결과는 Future 로 반환.
class BackgroundCalibrationRunner {
  static const _duration = Duration(seconds: 5);

  StreamSubscription<AccelerometerEvent>? _sub;
  Timer? _countdown;
  bool _running = false;

  bool get isRunning => _running;

  /// [onTick] : 남은 초 (5 → 4 → 3 → ... → 0). UI에 카운트다운 표시용.
  /// 반환 : 평균 tilt(°). 측정 실패면 null.
  Future<double?> sample({void Function(int remaining)? onTick}) async {
    if (_running) return null;
    _running = true;

    final tilts = <double>[];
    final completer = Completer<double?>();
    int remaining = _duration.inSeconds;
    onTick?.call(remaining);

    _sub = accelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval)
        .listen((e) {
      final tilt = atan2(e.y.abs(), sqrt(e.x * e.x + e.z * e.z)) * 180 / pi;
      tilts.add(tilt);
    }, onError: (e) {
      debugPrint('[BgCalibration] 센서 오류: $e');
    }, cancelOnError: false);

    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      onTick?.call(remaining);
      if (remaining <= 0) {
        t.cancel();
        _finish(tilts, completer);
      }
    });

    return completer.future;
  }

  Future<void> _finish(
      List<double> tilts, Completer<double?> completer) async {
    await _sub?.cancel();
    _sub = null;
    _countdown = null;
    _running = false;

    if (tilts.isEmpty) {
      completer.complete(null);
      return;
    }
    // 처음 0.5초(~25프레임)는 손이 자리잡는 동안이라 제외
    final stable = tilts.length > 25 ? tilts.sublist(25) : tilts;
    final avg = stable.reduce((a, b) => a + b) / stable.length;
    debugPrint('[BgCalibration] 완료 — 평균 ${avg.toStringAsFixed(1)}° '
        '(${stable.length} 샘플)');
    completer.complete(avg);
  }

  void cancel() {
    _sub?.cancel();
    _countdown?.cancel();
    _sub = null;
    _countdown = null;
    _running = false;
  }
}
