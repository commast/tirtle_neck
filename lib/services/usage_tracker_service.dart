import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_usage_record.dart';
import 'app_category_classifier.dart';
import 'context_detector.dart';

enum UsagePeriod { today, week, month }

class CategoryAggregate {
  final AppCategory category;
  final int totalSeconds;
  final int totalWarnings;
  final List<AppUsageRecord> apps; // 사용시간 내림차순

  CategoryAggregate({
    required this.category,
    required this.totalSeconds,
    required this.totalWarnings,
    required this.apps,
  });
}

class UsageAggregate {
  final int totalSeconds;
  final int totalWarnings;
  final List<int> hourlyWarnings; // length=24
  final List<CategoryAggregate> categories; // 사용시간 내림차순

  UsageAggregate({
    required this.totalSeconds,
    required this.totalWarnings,
    required this.hourlyWarnings,
    required this.categories,
  });
}

class UsageTrackerService extends ChangeNotifier {
  UsageTrackerService._();
  static final UsageTrackerService instance = UsageTrackerService._();

  static const _kKey = 'usage_history_v1';
  static const _retainDays = 35;

  final Map<String, DailyUsageSnapshot> _byDate = {};
  ContextDetector? _detector;
  VoidCallback? _snapshotListener;
  Timer? _flushTimer;

  String? _currentPkg;
  String _currentLabel = '';
  AppCategory _currentCategory = AppCategory.other;
  DateTime? _currentStart;

  bool _initialized = false;

  /// ContextDetector 의 snapshot ValueNotifier 를 구독해 포그라운드 앱 변경을
  /// 감지한다. EventChannel 을 직접 listen 하지 않는다 — Android 의
  /// receiveBroadcastStream 은 한 번에 하나의 핸들러만 허용해서 ContextDetector
  /// 와 충돌하기 때문.
  Future<void> init(ContextDetector detector) async {
    if (_initialized) return;
    _initialized = true;
    _detector = detector;
    await _load();
    await _autoSeedSparse();
    // 초기값 한 번 반영
    _consumeSnapshot();
    void listener() => _consumeSnapshot();
    _snapshotListener = listener;
    detector.snapshot.addListener(listener);
    // 주기적으로 현재 누적값을 디스크에 반영 (앱이 그대로 종료돼도 손실 최소화)
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _accrueCurrent();
      _save();
    });
  }

  void _consumeSnapshot() {
    final det = _detector;
    if (det == null) return;
    final snap = det.snapshot.value;
    final pkg = snap.foregroundPackage;
    if (pkg == _currentPkg) {
      // 라벨/카테고리만 최신값으로 업데이트 (시간 누적은 그대로)
      if (snap.foregroundLabel != null && snap.foregroundLabel!.isNotEmpty) {
        _currentLabel = snap.foregroundLabel!;
      }
      _currentCategory = snap.appCategory;
      return;
    }
    // 앱 전환: 직전 앱 시간 누적 후 현재 앱 갱신
    _accrueCurrent();
    _currentPkg = (pkg == null || pkg.isEmpty) ? null : pkg;
    _currentLabel = snap.foregroundLabel ?? '';
    _currentCategory = snap.appCategory;
    _currentStart = _currentPkg == null ? null : DateTime.now();
  }

  void _accrueCurrent() {
    final pkg = _currentPkg;
    final start = _currentStart;
    if (pkg == null || start == null) return;
    final now = DateTime.now();
    final elapsed = now.difference(start).inSeconds;
    if (elapsed <= 0) {
      _currentStart = now;
      return;
    }
    final snap = _todaySnapshot();
    final rec = snap.apps.putIfAbsent(
      pkg,
      () => AppUsageRecord(
        packageName: pkg,
        label: _currentLabel,
        category: _currentCategory,
      ),
    );
    rec.usageSeconds += elapsed;
    if (_currentLabel.isNotEmpty) rec.label = _currentLabel;
    rec.category = _currentCategory;
    _currentStart = now;
  }

  /// 외부에서 주의(caution) 단계 진입 시 1회 호출. 현재 포그라운드 앱과 시간대에 기록.
  /// 경고(risk)도 주의 카운트(warningCount) 에 포함됨. 경고만 별도 추적은 recordRisk().
  void recordWarning() {
    _accrueCurrent();
    final now = DateTime.now();
    final snap = _todaySnapshot();
    final hour = now.hour.clamp(0, 23);
    snap.hourlyWarnings[hour] += 1;
    final catList = snap.categoryHourlyWarnings[_currentCategory];
    if (catList != null) catList[hour] += 1;
    final pkg = _currentPkg;
    if (pkg != null) {
      final rec = snap.apps.putIfAbsent(
        pkg,
        () => AppUsageRecord(
          packageName: pkg,
          label: _currentLabel,
          category: _currentCategory,
        ),
      );
      rec.warningCount += 1;
    }
    _save();
    notifyListeners();
  }

  /// 경고(risk) 단계 발사 시 호출. recordWarning() 와 별개로 호출되며
  /// riskCount만 증가시킨다. (warningCount 는 호출 측에서 별도로 추가하지 않음 — 이미
  /// recordWarning 에서 누적됐다고 가정).
  void recordRisk() {
    _accrueCurrent();
    final snap = _todaySnapshot();
    final pkg = _currentPkg;
    if (pkg != null) {
      final rec = snap.apps.putIfAbsent(
        pkg,
        () => AppUsageRecord(
          packageName: pkg,
          label: _currentLabel,
          category: _currentCategory,
        ),
      );
      rec.riskCount += 1;
    }
    _save();
    notifyListeners();
  }

  /// 홈탭: 오늘 주의·경고가 가장 많았던 앱 (자세를 가장 나쁘게 만든 주범).
  /// 동률이면 사용 시간이 긴 앱 우선. 주의·경고 0회뿐이면 null 반환 → 빈 상태 표시.
  AppUsageRecord? topAppToday() {
    _accrueCurrent();
    final snap = _byDate[_dateKey(DateTime.now())];
    if (snap == null || snap.apps.isEmpty) return null;
    AppUsageRecord? top;
    for (final r in snap.apps.values) {
      if (r.warningCount <= 0) continue;
      if (top == null ||
          r.warningCount > top.warningCount ||
          (r.warningCount == top.warningCount && r.usageSeconds > top.usageSeconds)) {
        top = r;
      }
    }
    return top;
  }

  /// 홈탭 일별 그래프용: 오늘 24시간 동안 카테고리별 (주의+위험) 횟수.
  Map<AppCategory, List<int>> hourlyByCategoryToday() {
    _accrueCurrent();
    final snap = _byDate[_dateKey(DateTime.now())];
    final result = <AppCategory, List<int>>{
      for (final c in AppCategory.values) c: List<int>.filled(24, 0),
    };
    if (snap != null) {
      for (final e in snap.categoryHourlyWarnings.entries) {
        for (int i = 0; i < 24; i++) {
          result[e.key]![i] = e.value[i];
        }
      }
    }
    return result;
  }

  /// 홈탭 주별 그래프용: 이번 주 월~일 카테고리별 (주의+위험) 횟수.
  /// index 0 = 월, 6 = 일.
  Map<AppCategory, List<int>> weeklyByCategory() {
    _accrueCurrent();
    final now = DateTime.now();
    final mondayOffset = now.weekday - 1; // Mon=1 → 0
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: mondayOffset));
    final result = <AppCategory, List<int>>{
      for (final c in AppCategory.values) c: List<int>.filled(7, 0),
    };
    for (int i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      final snap = _byDate[_dateKey(d)];
      if (snap == null) continue;
      for (final r in snap.apps.values) {
        result[r.category]![i] += r.warningCount;
      }
    }
    return result;
  }

  /// 현재 시각 기준으로 데이터가 의미있는 마지막 인덱스 (이후는 미래라 그리지 않음).
  /// 일별: 현재 시각 (0~23). 주별: 오늘 요일 인덱스 (0~6, 월=0).
  int todayHourIndex() => DateTime.now().hour.clamp(0, 23);
  int todayWeekdayIndex() => (DateTime.now().weekday - 1).clamp(0, 6);

  /// 오늘 카테고리별 사용시간(초). 0인 카테고리도 포함.
  Map<AppCategory, int> categoryUsageToday() {
    _accrueCurrent();
    final result = <AppCategory, int>{
      for (final c in AppCategory.values) c: 0,
    };
    final snap = _byDate[_dateKey(DateTime.now())];
    if (snap == null) return result;
    for (final r in snap.apps.values) {
      result[r.category] = (result[r.category] ?? 0) + r.usageSeconds;
    }
    return result;
  }

  /// 이번 주 월~일 카테고리별 사용시간(초) + (주의+경고) 횟수.
  /// 각 리스트 길이 7, index 0=월. 미래 요일은 0 유지.
  ({
    Map<AppCategory, List<int>> usageSeconds,
    Map<AppCategory, List<int>> warnings,
    int lastIndex,
  }) dailyByCategoryThisWeek() {
    _accrueCurrent();
    final now = DateTime.now();
    final mondayOffset = now.weekday - 1;
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: mondayOffset));
    final usage = <AppCategory, List<int>>{
      for (final c in AppCategory.values) c: List<int>.filled(7, 0),
    };
    final warnings = <AppCategory, List<int>>{
      for (final c in AppCategory.values) c: List<int>.filled(7, 0),
    };
    for (int i = 0; i < 7; i++) {
      final snap = _byDate[_dateKey(monday.add(Duration(days: i)))];
      if (snap == null) continue;
      for (final r in snap.apps.values) {
        usage[r.category]![i] += r.usageSeconds;
        warnings[r.category]![i] += r.warningCount;
      }
    }
    return (
      usageSeconds: usage,
      warnings: warnings,
      lastIndex: now.weekday - 1,
    );
  }

  /// 최근 30일 카테고리별 일별 (주의+경고) 횟수.
  /// dayHasData[i] = true 면 그 날 앱 사용 데이터가 있음 (라인 연결 가능).
  /// false 면 라인 끊김 처리.
  ({
    List<bool> dayHasData,
    Map<AppCategory, List<int>> warnings,
    int lastIndex,
  }) dailyByCategoryThisMonth() {
    _accrueCurrent();
    final now = DateTime.now();
    final dayHasData = List<bool>.filled(30, false);
    final warnings = <AppCategory, List<int>>{
      for (final c in AppCategory.values) c: List<int>.filled(30, 0),
    };
    for (int i = 0; i < 30; i++) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 29 - i));
      final snap = _byDate[_dateKey(d)];
      if (snap == null || snap.apps.isEmpty) continue;
      dayHasData[i] = true;
      for (final r in snap.apps.values) {
        warnings[r.category]![i] += r.warningCount;
      }
    }
    return (
      dayHasData: dayHasData,
      warnings: warnings,
      lastIndex: 29,
    );
  }

  /// 이번 달 1일~말일 카테고리별 일별 주의 횟수.
  /// dayHasData[i] = true 면 그 날 실제 스냅샷이 존재. false 면 차트에서 스킵 가능.
  /// todayIndex = today.day - 1 (0-based). 미래 날짜는 0 유지.
  ({
    Map<AppCategory, List<int>> warnings,
    List<bool> dayHasData,
    int daysInMonth,
    int todayIndex,
  }) dailyByCategoryThisCalendarMonth() {
    _accrueCurrent();
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final todayIdx = now.day - 1;

    final warnings = <AppCategory, List<int>>{
      for (final c in AppCategory.values) c: List<int>.filled(daysInMonth, 0),
    };
    final hasData = List<bool>.filled(daysInMonth, false);
    for (int i = 0; i <= todayIdx; i++) {
      final snap = _byDate[_dateKey(DateTime(y, m, i + 1))];
      if (snap == null || snap.apps.isEmpty) continue;
      hasData[i] = true;
      for (final r in snap.apps.values) {
        warnings[r.category]![i] += r.warningCount;
      }
    }
    return (
      warnings: warnings,
      dayHasData: hasData,
      daysInMonth: daysInMonth,
      todayIndex: todayIdx,
    );
  }

  // ── 발표용 샘플 데이터 (sparse, 2일 간격) ─────────────────
  // 진짜 데이터가 없는 날에만 채워넣어 곡선이 자연스럽게 보이도록 한다.
  static const _seedDays = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25];
  static const _seedCats = [
    AppCategory.video, AppCategory.game, AppCategory.social, AppCategory.study,
  ];
  static const _seedWarn = <AppCategory, List<int>>{
    AppCategory.video:  [3, 4, 5, 6, 7, 8, 8, 7, 6, 5, 5, 6, 7],
    AppCategory.game:   [4, 5, 6, 6, 5, 4, 5, 6, 7, 7, 6, 5, 4],
    AppCategory.social: [8, 9,10, 9, 8, 6, 5, 4, 5, 6, 7, 8, 9],
    AppCategory.study:  [2, 2, 3, 4, 5, 5, 4, 3, 3, 4, 5, 6, 6],
  };
  static const _seedSec = <AppCategory, List<int>>{
    AppCategory.video:  [2400, 3600, 4800, 5400, 6600, 7200, 7200, 6000, 5400, 4200, 4200, 5400, 6000],
    AppCategory.game:   [2400, 3000, 3600, 4200, 3600, 2400, 3000, 4200, 5400, 4800, 3600, 3000, 2400],
    AppCategory.social: [4800, 6000, 7200, 6600, 5400, 3600, 2400, 1800, 2400, 3600, 4800, 6000, 7200],
    AppCategory.study:  [1800, 1800, 2400, 3000, 3600, 4200, 3600, 2400, 2400, 3000, 3600, 4800, 5400],
  };
  static const _seedApp = <AppCategory, (String, String)>{
    AppCategory.video:  ('com.google.android.youtube', 'YouTube'),
    AppCategory.game:   ('com.mojang.minecraftpe', 'Minecraft'),
    AppCategory.social: ('com.instagram.android', 'Instagram'),
    AppCategory.study:  ('com.google.android.apps.docs', 'Google Docs'),
  };

  /// 이번 달의 지정된 날짜들 중, 아직 스냅샷이 없는 날에만 샘플 데이터를 주입한다.
  /// 실제 사용 데이터는 보존된다.
  Future<void> _autoSeedSparse() async {
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    var changed = false;
    for (int i = 0; i < _seedDays.length; i++) {
      final day = _seedDays[i];
      if (day >= now.day) break; // 오늘 또는 미래는 시드하지 않음
      final key = _dateKey(DateTime(y, m, day));
      if (_byDate.containsKey(key)) continue; // 실제 데이터 보존
      final snap = DailyUsageSnapshot(date: key);
      for (final cat in _seedCats) {
        final (pkg, label) = _seedApp[cat]!;
        final warn = _seedWarn[cat]![i];
        final secs = _seedSec[cat]![i];
        snap.apps[pkg] = AppUsageRecord(
          packageName: pkg, label: label, category: cat,
          usageSeconds: secs, warningCount: warn,
        );
        if (warn > 0) {
          final h1 = (9 + cat.index * 3) % 24;
          final h2 = (15 + cat.index * 2) % 24;
          snap.hourlyWarnings[h1] += warn ~/ 2;
          snap.hourlyWarnings[h2] += warn - warn ~/ 2;
          snap.categoryHourlyWarnings[cat]![h1] += warn ~/ 2;
          snap.categoryHourlyWarnings[cat]![h2] += warn - warn ~/ 2;
        }
      }
      _byDate[key] = snap;
      changed = true;
    }
    if (changed) await _save();
  }

  DailyUsageSnapshot _todaySnapshot() {
    final key = _dateKey(DateTime.now());
    return _byDate.putIfAbsent(key, () => DailyUsageSnapshot(date: key));
  }

  static String _dateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  UsageAggregate aggregate(UsagePeriod period) {
    _accrueCurrent();
    final now = DateTime.now();
    final days = switch (period) {
      UsagePeriod.today => 1,
      UsagePeriod.week => 7,
      UsagePeriod.month => 30,
    };
    final keys = <String>{};
    for (int i = 0; i < days; i++) {
      keys.add(_dateKey(now.subtract(Duration(days: i))));
    }
    final mergedApps = <String, AppUsageRecord>{};
    final hourly = List<int>.filled(24, 0);
    for (final k in keys) {
      final snap = _byDate[k];
      if (snap == null) continue;
      for (int h = 0; h < 24; h++) {
        hourly[h] += snap.hourlyWarnings[h];
      }
      for (final e in snap.apps.entries) {
        final acc = mergedApps.putIfAbsent(
          e.key,
          () => AppUsageRecord(
            packageName: e.value.packageName,
            label: e.value.label,
            category: e.value.category,
          ),
        );
        acc.usageSeconds += e.value.usageSeconds;
        acc.warningCount += e.value.warningCount;
        if (e.value.label.isNotEmpty) acc.label = e.value.label;
        acc.category = e.value.category;
      }
    }
    final byCat = <AppCategory, List<AppUsageRecord>>{};
    for (final r in mergedApps.values) {
      byCat.putIfAbsent(r.category, () => []).add(r);
    }
    final cats = byCat.entries.map((e) {
      final apps = e.value..sort((a, b) => b.usageSeconds.compareTo(a.usageSeconds));
      final secs = apps.fold<int>(0, (s, a) => s + a.usageSeconds);
      final warns = apps.fold<int>(0, (s, a) => s + a.warningCount);
      return CategoryAggregate(
        category: e.key,
        totalSeconds: secs,
        totalWarnings: warns,
        apps: apps,
      );
    }).toList()
      ..sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));

    final totalSec = cats.fold<int>(0, (s, c) => s + c.totalSeconds);
    final totalWarn = cats.fold<int>(0, (s, c) => s + c.totalWarnings);
    return UsageAggregate(
      totalSeconds: totalSec,
      totalWarnings: totalWarn,
      hourlyWarnings: hourly,
      categories: cats,
    );
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      for (final e in list) {
        final snap = DailyUsageSnapshot.fromJson(Map<String, dynamic>.from(e as Map));
        if (snap.date.isNotEmpty) _byDate[snap.date] = snap;
      }
      _pruneOld();
    } catch (e) {
      debugPrint('[UsageTracker] 로드 실패: $e');
    }
  }

  Future<void> _save() async {
    try {
      _pruneOld();
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_byDate.values.map((s) => s.toJson()).toList());
      await prefs.setString(_kKey, json);
    } catch (e) {
      debugPrint('[UsageTracker] 저장 실패: $e');
    }
  }

  void _pruneOld() {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: _retainDays));
    _byDate.removeWhere((k, _) {
      final parts = k.split('-');
      if (parts.length != 3) return true;
      final dt = DateTime.tryParse(k);
      if (dt == null) return true;
      return dt.isBefore(cutoff);
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    final l = _snapshotListener;
    if (l != null) {
      _detector?.snapshot.removeListener(l);
    }
    _snapshotListener = null;
    _detector = null;
    _accrueCurrent();
    _save();
    super.dispose();
  }
}
