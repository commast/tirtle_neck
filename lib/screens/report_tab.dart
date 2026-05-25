import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/app_usage_record.dart';
import '../services/app_category_classifier.dart';
import '../services/usage_tracker_service.dart';

class ReportTab extends StatefulWidget {
  const ReportTab({super.key});

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  UsagePeriod _period = UsagePeriod.today;
  final Set<AppCategory> _expanded = {};

  @override
  void initState() {
    super.initState();
    UsageTrackerService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    UsageTrackerService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final agg = UsageTrackerService.instance.aggregate(_period);
    final isEmpty = agg.totalSeconds == 0 && agg.totalWarnings == 0;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('앱 사용·자세 리포트',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('주의 ${agg.totalWarnings}회',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _periodToggle(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (isEmpty)
                  _emptyState()
                else ...[
                  _summaryCard(agg),
                  const SizedBox(height: 12),
                  _periodChartCard(),
                  const SizedBox(height: 12),
                  for (final c in agg.categories) ...[
                    _categoryCard(c, agg.totalWarnings, agg.totalSeconds),
                    const SizedBox(height: 10),
                  ],
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodToggle() {
    Widget btn(UsagePeriod p, String label) {
      final sel = _period == p;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _period = p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: sel ? kGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    color: sel ? Colors.white : Colors.grey[600],
                    fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                  )),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        btn(UsagePeriod.today, '오늘'),
        btn(UsagePeriod.week, '주간'),
        btn(UsagePeriod.month, '월간'),
      ]),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: [
        Icon(Icons.insights_rounded, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('아직 데이터가 없습니다',
            style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          '앱 사용 기록과 자세 주의 횟수가 수집되면\n여기에 카테고리별로 표시됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
        ),
        const SizedBox(height: 4),
        Text(
          '※ 사용량 추적은 PACKAGE_USAGE_STATS 권한이 필요합니다.\n프로필 탭에서 허용 후 잠시 기다려주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey[400], height: 1.4),
        ),
      ]),
    );
  }

  Widget _summaryCard(UsageAggregate agg) {
    final ratePerHour = agg.totalSeconds == 0
        ? 0.0
        : agg.totalWarnings / (agg.totalSeconds / 3600.0);
    return _card(
      title: '요약',
      subtitle: 'SUMMARY',
      child: Row(children: [
        Expanded(child: _summaryBox('총 사용시간', _formatDuration(agg.totalSeconds), kGreen)),
        const SizedBox(width: 10),
        Expanded(child: _summaryBox('총 주의', '${agg.totalWarnings}회', Colors.orange)),
        const SizedBox(width: 10),
        Expanded(child: _summaryBox('시간당 주의', '${ratePerHour.toStringAsFixed(1)}회', Colors.red)),
      ]),
    );
  }

  Widget _summaryBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ]),
    );
  }

  Widget _periodChartCard() {
    final title = switch (_period) {
      UsagePeriod.today => '카테고리별 사용 비율',
      UsagePeriod.week => '요일별 사용량 (주의·경고 표시)',
      UsagePeriod.month => '카테고리별 일별 주의 추이',
    };
    final subtitle = switch (_period) {
      UsagePeriod.today => 'CATEGORY SHARE',
      UsagePeriod.week => 'WEEKLY USAGE',
      UsagePeriod.month => 'MONTHLY TREND',
    };
    Widget chart;
    switch (_period) {
      case UsagePeriod.today:
        chart = _todayDonut();
      case UsagePeriod.week:
        chart = _weekStackedBar();
      case UsagePeriod.month:
        chart = _monthLineChart();
    }
    return _card(
      title: title,
      subtitle: subtitle,
      child: SizedBox(height: 200, child: chart),
    );
  }

  Widget _todayDonut() {
    final usage = UsageTrackerService.instance.categoryUsageToday();
    final entries = _chartCategories
        .map((c) => MapEntry(c, usage[c] ?? 0))
        .where((e) => e.value > 0)
        .toList();
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) {
      return Center(
        child: Text('오늘 사용 기록이 없어요.',
            style: TextStyle(color: Colors.grey[400])),
      );
    }
    final sections = entries.map((e) {
      final pct = e.value * 100.0 / total;
      return PieChartSectionData(
        color: _categoryColor(e.key),
        value: e.value.toDouble(),
        title: '${_categoryEmoji(e.key)} ${pct.toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
        ),
        radius: 50,
      );
    }).toList();
    return Row(children: [
      Expanded(
        child: PieChart(
          PieChartData(
            sections: sections,
            sectionsSpace: 2,
            centerSpaceRadius: 38,
            startDegreeOffset: -90,
            centerSpaceColor: Colors.white,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('총 사용', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          Text(_formatDuration(total),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final e in entries) Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _categoryColor(e.key), shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(_categoryLabel(e.key),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text(_formatDuration(e.value),
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ]),
          ),
        ],
      ),
      const SizedBox(width: 4),
    ]);
  }

  Widget _weekStackedBar() {
    final data = UsageTrackerService.instance.dailyByCategoryThisWeek();
    const dayLabels = ['월', '화', '수', '목', '금', '토', '일'];
    // 분 단위로 변환 (y축 가독성)
    final groups = <BarChartGroupData>[];
    double maxMinutes = 0;
    for (int i = 0; i < 7; i++) {
      double cumulative = 0;
      final stacks = <BarChartRodStackItem>[];
      for (final c in _chartCategories) {
        final secs = data.usageSeconds[c]?[i] ?? 0;
        if (secs <= 0) continue;
        final minutes = secs / 60.0;
        stacks.add(BarChartRodStackItem(
          cumulative, cumulative + minutes, _categoryColor(c),
        ));
        cumulative += minutes;
      }
      if (cumulative > maxMinutes) maxMinutes = cumulative;
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: cumulative,
            width: 22,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            rodStackItems: stacks,
            color: stacks.isEmpty ? Colors.grey.shade200 : null,
          ),
        ],
      ));
    }
    if (maxMinutes <= 0) {
      return Center(
        child: Text('이번 주 사용 기록이 없어요.',
            style: TextStyle(color: Colors.grey[400])),
      );
    }
    final maxY = (maxMinutes * 1.15).ceilToDouble();

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      // BarChart 내부 패딩(타이틀 라벨 공간) 추정 — leftAxis 32, bottom 22, top 8
      const leftAxis = 32.0;
      const bottomAxis = 22.0;
      const topPad = 8.0;
      final plotW = w - leftAxis;
      final plotH = h - bottomAxis - topPad;
      final groupW = plotW / 7;

      // 주의+경고 합계 — 막대 위 텍스트
      final dayTotals = List<int>.generate(7, (i) {
        int s = 0;
        for (final c in _chartCategories) {
          s += data.warnings[c]?[i] ?? 0;
        }
        return s;
      });

      return Stack(children: [
        BarChart(
          BarChartData(
            maxY: maxY,
            barGroups: groups,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: Colors.grey.shade200, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: leftAxis,
                  interval: maxY / 4,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('${v.toInt()}m',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: bottomAxis,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i > 6) return const SizedBox.shrink();
                    final isToday = i == data.lastIndex;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        dayLabels[i],
                        style: TextStyle(
                          fontSize: 11,
                          color: isToday ? kGreen : Colors.grey[600],
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(enabled: false),
          ),
        ),
        // 스택 영역 위에 주의+경고 횟수 오버레이
        ..._buildWeekOverlayLabels(
          data: data,
          totals: dayTotals,
          maxY: maxY,
          plotW: plotW,
          plotH: plotH,
          leftAxis: leftAxis,
          topPad: topPad,
          groupW: groupW,
        ),
      ]);
    });
  }

  List<Widget> _buildWeekOverlayLabels({
    required ({
      Map<AppCategory, List<int>> usageSeconds,
      Map<AppCategory, List<int>> warnings,
      int lastIndex,
    }) data,
    required List<int> totals,
    required double maxY,
    required double plotW,
    required double plotH,
    required double leftAxis,
    required double topPad,
    required double groupW,
  }) {
    final widgets = <Widget>[];
    for (int i = 0; i < 7; i++) {
      final cx = leftAxis + groupW * (i + 0.5);
      double cumulative = 0;
      for (final c in _chartCategories) {
        final secs = data.usageSeconds[c]?[i] ?? 0;
        if (secs <= 0) continue;
        final minutes = secs / 60.0;
        final segTop = topPad + plotH * (1 - (cumulative + minutes) / maxY);
        final segBottom = topPad + plotH * (1 - cumulative / maxY);
        final segH = segBottom - segTop;
        final warn = data.warnings[c]?[i] ?? 0;
        if (segH >= 18 && warn > 0) {
          widgets.add(Positioned(
            left: cx - 18,
            top: segTop + segH / 2 - 7,
            child: SizedBox(
              width: 36,
              child: Text(
                '$warn',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ));
        }
        cumulative += minutes;
      }
      // 막대 위 총합
      if (totals[i] > 0) {
        final topY = topPad + plotH * (1 - cumulative / maxY);
        widgets.add(Positioned(
          left: cx - 24,
          top: (topY - 14).clamp(0.0, plotH),
          child: SizedBox(
            width: 48,
            child: Text(
              '총 ${totals[i]}회',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ));
      }
    }
    return widgets;
  }

  Widget _monthLineChart() {
    final data = UsageTrackerService.instance.dailyByCategoryThisMonth();
    // 데이터 있는 카테고리만 라인 생성
    final lines = <LineChartBarData>[];
    int maxV = 0;
    for (final c in _chartCategories) {
      final list = data.warnings[c]!;
      // 데이터 있는 날들의 (x, y) 만 모음 → 라인 끊김
      final spots = <FlSpot>[];
      for (int i = 0; i <= data.lastIndex; i++) {
        if (!data.dayHasData[i]) {
          // 끊김: 현재 spot 누적 끊기 위해 라인을 분리하려면 separate line 필요.
          // 여기선 다음 데이터-있는 날까지 건너뛰며 누적.
          continue;
        }
        final v = list[i];
        if (v > maxV) maxV = v;
        spots.add(FlSpot(i.toDouble(), v.toDouble()));
      }
      if (spots.isEmpty) continue;
      lines.add(LineChartBarData(
        spots: spots,
        isCurved: false,
        color: _categoryColor(c),
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (s, _, _, _) => FlDotCirclePainter(
            radius: 2,
            color: _categoryColor(c),
            strokeWidth: 0,
          ),
        ),
      ));
    }
    if (lines.isEmpty) {
      return Center(
        child: Text('최근 30일 데이터가 없어요.',
            style: TextStyle(color: Colors.grey[400])),
      );
    }
    if (maxV < 4) maxV = 4;

    return Column(children: [
      Expanded(
        child: LineChart(
          LineChartData(
            minX: 0, maxX: 29,
            minY: 0, maxY: maxV.toDouble(),
            lineBarsData: lines,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: (maxV / 4).clamp(1, double.infinity).toDouble(),
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: Colors.grey.shade200, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: (maxV / 4).clamp(1, double.infinity).toDouble(),
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text('${v.toInt()}',
                        style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: 7,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i > 29) return const SizedBox.shrink();
                    final d = DateTime.now().subtract(Duration(days: 29 - i));
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${d.month}/${d.day}',
                          style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: const LineTouchData(enabled: false),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 10, runSpacing: 4, children: [
        for (final c in _chartCategories)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: _categoryColor(c), shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text('${_categoryEmoji(c)} ${_categoryLabel(c)}',
                style: TextStyle(fontSize: 10, color: Colors.grey[700])),
          ]),
      ]),
    ]);
  }

  // 차트에 표시할 4 카테고리 (other 제외)
  static const _chartCategories = [
    AppCategory.video,
    AppCategory.game,
    AppCategory.social,
    AppCategory.study,
  ];

  Widget _categoryCard(CategoryAggregate cat, int totalWarn, int totalSec) {
    final expanded = _expanded.contains(cat.category);
    final warnPct = totalWarn == 0 ? 0 : (cat.totalWarnings * 100 / totalWarn).round();
    final timePct = totalSec == 0 ? 0 : (cat.totalSeconds * 100 / totalSec).round();
    final color = _categoryColor(cat.category);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() {
            if (expanded) {
              _expanded.remove(cat.category);
            } else {
              _expanded.add(cat.category);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(_categoryEmoji(cat.category),
                    style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_categoryLabel(cat.category),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDuration(cat.totalSeconds)} · 주의 ${cat.totalWarnings}회 ($warnPct%)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (timePct / 100).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: expanded ? 0.5 : 0,
                child: Icon(Icons.expand_more_rounded, color: Colors.grey[500]),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Column(children: [
                    Divider(color: Colors.grey[200], height: 1),
                    const SizedBox(height: 8),
                    for (final app in cat.apps) _appRow(app, cat.totalWarnings, color),
                  ]),
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _appRow(AppUsageRecord app, int catTotalWarn, Color color) {
    final ratio = catTotalWarn == 0 ? 0 : (app.warningCount * 100 / catTotalWarn).round();
    final label = app.label.isEmpty ? app.packageName : app.label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 8),
        Text(_formatDuration(app.usageSeconds),
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(width: 12),
        SizedBox(
          width: 70,
          child: Text(
            '주의 ${app.warningCount}회 ($ratio%)',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              color: app.warningCount > 0 ? Colors.orange[800] : Colors.grey[400],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _card({required String title, required String subtitle, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey[400], letterSpacing: 0.5)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: child,
        ),
      ]),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  final mm = m % 60;
  return mm == 0 ? '${h}h' : '${h}h ${mm}m';
}

String _categoryEmoji(AppCategory c) => switch (c) {
      AppCategory.video => '📺',
      AppCategory.game => '🎮',
      AppCategory.social => '💬',
      AppCategory.study => '📚',
      AppCategory.other => '📦',
    };

String _categoryLabel(AppCategory c) => switch (c) {
      AppCategory.video => '영상',
      AppCategory.game => '게임',
      AppCategory.social => 'SNS',
      AppCategory.study => '학습/업무',
      AppCategory.other => '기타',
    };

Color _categoryColor(AppCategory c) => switch (c) {
      AppCategory.video => const Color(0xFFE53935),
      AppCategory.game => const Color(0xFF8E24AA),
      AppCategory.social => const Color(0xFF1E88E5),
      AppCategory.study => const Color(0xFF00897B),
      AppCategory.other => const Color(0xFF757575),
    };

