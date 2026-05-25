import '../services/app_category_classifier.dart';

class AppUsageRecord {
  final String packageName;
  String label;
  AppCategory category;
  int usageSeconds;
  int warningCount;

  AppUsageRecord({
    required this.packageName,
    required this.label,
    required this.category,
    this.usageSeconds = 0,
    this.warningCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'pkg': packageName,
        'label': label,
        'cat': category.name,
        'sec': usageSeconds,
        'warn': warningCount,
      };

  static AppUsageRecord fromJson(Map<String, dynamic> m) => AppUsageRecord(
        packageName: m['pkg'] as String? ?? '',
        label: m['label'] as String? ?? '',
        category: _catFromName(m['cat'] as String? ?? 'other'),
        usageSeconds: (m['sec'] as num?)?.toInt() ?? 0,
        warningCount: (m['warn'] as num?)?.toInt() ?? 0,
      );
}

class DailyUsageSnapshot {
  final String date;
  final Map<String, AppUsageRecord> apps;
  final List<int> hourlyWarnings;
  final Map<AppCategory, List<int>> categoryHourlyWarnings;

  DailyUsageSnapshot({
    required this.date,
    Map<String, AppUsageRecord>? apps,
    List<int>? hourlyWarnings,
    Map<AppCategory, List<int>>? categoryHourlyWarnings,
  })  : apps = apps ?? {},
        hourlyWarnings = hourlyWarnings ?? List<int>.filled(24, 0),
        categoryHourlyWarnings = categoryHourlyWarnings ??
            {for (final c in AppCategory.values) c: List<int>.filled(24, 0)};

  Map<String, dynamic> toJson() => {
        'date': date,
        'apps': apps.values.map((e) => e.toJson()).toList(),
        'hourly': hourlyWarnings,
        'cat_hourly': {
          for (final e in categoryHourlyWarnings.entries) e.key.name: e.value,
        },
      };

  static DailyUsageSnapshot fromJson(Map<String, dynamic> m) {
    final apps = <String, AppUsageRecord>{};
    for (final raw in (m['apps'] as List? ?? const [])) {
      final r = AppUsageRecord.fromJson(Map<String, dynamic>.from(raw as Map));
      apps[r.packageName] = r;
    }
    final hourly = ((m['hourly'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final filled = List<int>.filled(24, 0);
    for (int i = 0; i < hourly.length && i < 24; i++) {
      filled[i] = hourly[i];
    }
    final catHourly = <AppCategory, List<int>>{
      for (final c in AppCategory.values) c: List<int>.filled(24, 0),
    };
    final rawCat = m['cat_hourly'];
    if (rawCat is Map) {
      for (final entry in rawCat.entries) {
        final c = _catFromName(entry.key as String);
        final list = (entry.value as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList();
        final dst = catHourly[c]!;
        for (int i = 0; i < list.length && i < 24; i++) {
          dst[i] = list[i];
        }
      }
    }
    return DailyUsageSnapshot(
      date: m['date'] as String? ?? '',
      apps: apps,
      hourlyWarnings: filled,
      categoryHourlyWarnings: catHourly,
    );
  }
}

AppCategory _catFromName(String n) {
  for (final c in AppCategory.values) {
    if (c.name == n) return c;
  }
  return AppCategory.other;
}
