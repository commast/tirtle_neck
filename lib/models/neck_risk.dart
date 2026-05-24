/// IMU 센서 기반 거북목 위험도 — 3단계.
enum NeckRiskLevel { normal, caution, risk }

/// 점수 분해와 함께 노출. 디버그 카드 + 모드별 가중치 분석 용도.
class NeckRiskState {
  final NeckRiskLevel level;
  final int    score;          // 0~100 (modeWeight 적용 후 최종)
  final int    rawScore;       // 가중치 적용 전 0~100
  final int    pitchScore;     // 0~40
  final int    gyroScore;      // 0~20
  final int    durationScore;  // 0~40
  final int    stillnessBonus; // 0~40 (게임/영상 모드 한정 보너스)
  final double tiltDeg;        // 폰의 수평 기준 기울기 (90°=수직, 0°=수평)
  final double gyroVariance;   // 자이로 분산
  final int    sustainedSec;   // 같은 자세 유지 초
  final int    stillSec;       // 자이로 거의 0 유지 초 (만보기 역방향)
  final double modeWeight;     // 컨텍스트별 가중치

  const NeckRiskState({
    required this.level,
    required this.score,
    required this.rawScore,
    required this.pitchScore,
    required this.gyroScore,
    required this.durationScore,
    required this.stillnessBonus,
    required this.tiltDeg,
    required this.gyroVariance,
    required this.sustainedSec,
    required this.stillSec,
    required this.modeWeight,
  });

  static const initial = NeckRiskState(
    level: NeckRiskLevel.normal,
    score: 0,
    rawScore: 0,
    pitchScore: 0,
    gyroScore: 0,
    durationScore: 0,
    stillnessBonus: 0,
    tiltDeg: 90.0,
    gyroVariance: 0.0,
    sustainedSec: 0,
    stillSec: 0,
    modeWeight: 1.0,
  );
}

extension NeckRiskLevelExt on NeckRiskLevel {
  /// 0~50=normal, 51~70=caution, 71+=risk
  /// (사용자 보고 기반 조정: 일반 폰 사용은 정상 유지, 의미있는 경고만 caution)
  static NeckRiskLevel fromScore(int score) {
    if (score >= 71) return NeckRiskLevel.risk;
    if (score >= 51) return NeckRiskLevel.caution;
    return NeckRiskLevel.normal;
  }

  String get label => switch (this) {
    NeckRiskLevel.normal  => '정상',
    NeckRiskLevel.caution => '주의',
    NeckRiskLevel.risk    => '위험',
  };

  /// 오버레이 배경색
  String get colorHex => switch (this) {
    NeckRiskLevel.normal  => '#00C896', // 초록
    NeckRiskLevel.caution => '#FFA000', // 주황
    NeckRiskLevel.risk    => '#E53935', // 빨강
  };

  /// 위험 단계에서만 카메라 트리거를 허용한다.
  bool get isCameraEligible => this == NeckRiskLevel.risk;
}
