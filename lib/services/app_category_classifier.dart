enum AppCategory { video, game, social, study, other }

extension AppCategoryLabel on AppCategory {
  String get name => switch (this) {
    AppCategory.video  => 'video',
    AppCategory.game   => 'game',
    AppCategory.social => 'social',
    AppCategory.study  => 'study',
    AppCategory.other  => 'other',
  };
}

class AppCategoryClassifier {
  // 패키지명 부분 일치 기반 휴리스틱. lowercase로 비교.
  static const _video = [
    'youtube', 'netflix', 'tiktok', 'twitch', 'watcha',
    'wavve', 'tving', 'disney', 'primevideo', 'coupangplay',
  ];
  static const _social = [
    'instagram', 'kakao', 'twitter', 'facebook', 'line.android',
    'snapchat', 'threads', 'discord', 'telegram', 'whatsapp',
    'reddit', 'pinterest', 'tumblr',
  ];
  static const _study = [
    'notion', 'docs', 'slides', 'classroom', 'zoom',
    'evernote', 'onenote', 'goodnotes', 'anki', 'memrise',
  ];
  // 게임 화이트리스트 (대표적인 패키지). 'game' 키워드도 추가로 체크.
  static const _gameKeywords = ['game', 'pubg', 'lineage', 'genshin', 'lol', 'cocgame', 'krafton'];

  /// [systemCategory]는 Android ApplicationInfo.category 값
  /// ("game"/"video"/"audio"/"social"/"undefined" 등).
  /// 시스템이 명시한 카테고리가 있으면 그걸 신뢰하고,
  /// "undefined"인 경우에만 패키지명 키워드로 폴백한다.
  static AppCategory classify(String pkg, {String systemCategory = 'undefined'}) {
    switch (systemCategory) {
      case 'game':   return AppCategory.game;
      case 'video':  return AppCategory.video;
      case 'audio':  return AppCategory.video;  // 음악 앱도 시청 카테고리로 묶음
      case 'social': return AppCategory.social;
      case 'productivity': return AppCategory.study;
    }
    final p = pkg.toLowerCase();
    if (_video.any(p.contains))        return AppCategory.video;
    if (_social.any(p.contains))       return AppCategory.social;
    if (_study.any(p.contains))        return AppCategory.study;
    if (_gameKeywords.any(p.contains)) return AppCategory.game;
    return AppCategory.other;
  }
}
