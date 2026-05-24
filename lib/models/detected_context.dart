enum DetectedContext {
  normal,
  desk,
  watchingVideo,
  gaming,
  social,
  studying,
  onPhoneCall,
}

extension DetectedContextExt on DetectedContext {
  /// pitch 임계값 (도). infinite 면 거북목 감지 비활성.
  double get pitchThreshold => switch (this) {
    DetectedContext.watchingVideo => 22.0,
    DetectedContext.gaming        => 22.0,
    DetectedContext.social        => 22.0,
    DetectedContext.desk          => 22.0,
    DetectedContext.studying      => 25.0,
    DetectedContext.normal        => 30.0,
    DetectedContext.onPhoneCall   => double.infinity,
  };

  bool get isMonitoringActive => pitchThreshold.isFinite;

  /// 모드별 거북목 위험도 가중치.
  /// 소셜 1.2, 학습 1.1, 게임 1.0, 영상 0.9, 기타 1.0
  double get riskWeight => switch (this) {
    DetectedContext.social        => 1.2,
    DetectedContext.studying      => 1.1,
    DetectedContext.gaming        => 1.0,
    DetectedContext.watchingVideo => 0.9,
    _                             => 1.0,
  };

  /// 카메라를 사용할 수 있는 모드인지. 게임·영상에서만 사용자 옵트인 허용.
  bool get supportsCamera =>
      this == DetectedContext.gaming || this == DetectedContext.watchingVideo;

  /// 오버레이/디버그에 표시할 한국어 라벨 — 앱 카테고리는 "X 모드" 통일.
  String get label => switch (this) {
    DetectedContext.normal        => '일반',
    DetectedContext.desk          => '책상 모드',
    DetectedContext.watchingVideo => '영상 모드',
    DetectedContext.gaming        => '게임 모드',
    DetectedContext.social        => '소셜 모드',
    DetectedContext.studying      => '학습 모드',
    DetectedContext.onPhoneCall   => '통화 중',
  };

  /// 앱 카테고리 컨텍스트는 실제 앱 이름을 별도로 받아 표시하므로
  /// 여기서 라벨을 직접 반환하지 않고 main에서 합성한다.
  bool get usesAppLabel =>
      this == DetectedContext.watchingVideo ||
      this == DetectedContext.gaming ||
      this == DetectedContext.social ||
      this == DetectedContext.studying;

  /// 오버레이에 표시할 부가 텍스트 — normal은 표시 안 함.
  String? get overlayLabel => this == DetectedContext.normal ? null : label;

  /// 오버레이 모드 칩의 배경색.
  /// 영상=보라, 게임=파랑, 소셜=하늘, 학습=초록.
  String get modeColorHex => switch (this) {
    DetectedContext.watchingVideo => '#9C27B0', // 보라
    DetectedContext.gaming        => '#2196F3', // 파랑
    DetectedContext.social        => '#03A9F4', // 하늘
    DetectedContext.studying      => '#4CAF50', // 초록
    DetectedContext.desk          => '#607D8B', // 회청
    DetectedContext.onPhoneCall   => '#795548', // 갈색
    DetectedContext.normal        => '#9E9E9E', // 회색 (대기)
  };
}
