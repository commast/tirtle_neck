import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/app_usage_record.dart';
import '../services/app_category_classifier.dart';
import '../services/usage_tracker_service.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _weeklyView = false;

  // 그래프에 표시할 4개 카테고리 (other 제외)
  static const _chartCategories = [
    AppCategory.video,
    AppCategory.game,
    AppCategory.social,
    AppCategory.study,
  ];

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
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                _buildAppBarRow(),
                const SizedBox(height: 20),
                _buildTopAppCard(),
                const SizedBox(height: 24),
                _buildCategoryChartSection(),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarRow() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('안녕하세요!',
          style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      const Text('포스처가드',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildTopAppCard() {
    final top = UsageTrackerService.instance.topAppToday();
    final hasData = top != null && top.warningCount > 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C896), Color(0xFF00A878)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: kGreen.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: hasData
          ? _topAppContent(top)
          : _topAppEmptyContent(),
    );
  }

  Widget _topAppContent(AppUsageRecord top) {
    final label = top.label.isEmpty ? top.packageName : top.label;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('오늘 자세가 가장 나빴던 앱',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_categoryEmoji(top.category)} ${_categoryLabel(top.category)}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Text(_formatDuration(top.usageSeconds),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _miniStat('총 알림', '${top.warningCount}회')),
            const SizedBox(width: 10),
            Expanded(child: _miniStat(
              '주의 / 경고',
              '${top.cautionCount} / ${top.riskCount}',
            )),
          ]),
        ]),
      ),
    ]);
  }

  Widget _topAppEmptyContent() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('오늘 자세가 가장 나빴던 앱',
          style: TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: 16),
      Text(
        '오늘은 아직 주의·경고가 없어요.\n좋은 자세를 유지하고 계세요!',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, height: 1.4),
      ),
    ]);
  }

  Widget _miniStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildCategoryChartSection() {
    final tracker = UsageTrackerService.instance;
    final rawData = _weeklyView
        ? tracker.weeklyByCategory()
        : tracker.hourlyByCategoryToday();
    final lastIdx = _weeklyView ? tracker.todayWeekdayIndex() : tracker.todayHourIndex();
    final slots = _weeklyView ? 7 : 24;

    int maxV = 4;
    final lines = <LineChartBarData>[];
    for (final c in _chartCategories) {
      final list = rawData[c];
      if (list == null) continue;
      final spots = <FlSpot>[];
      for (int i = 0; i <= lastIdx; i++) {
        final v = list[i];
        if (v > maxV) maxV = v;
        spots.add(FlSpot(i.toDouble(), v.toDouble()));
      }
      if (spots.isEmpty) continue;
      final color = _categoryColor(c);
      lines.add(LineChartBarData(
        spots: spots,
        isCurved: false,
        color: color,
        barWidth: 1.5,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (s, _, _, _) => FlDotCirclePainter(
            radius: s.y > 0 ? 3.0 : 1.5,
            color: s.y > 0 ? color : Colors.transparent,
            strokeWidth: s.y > 0 ? 1.5 : 0,
            strokeColor: Colors.white,
          ),
        ),
      ));
    }

    // 주별 x축 라벨
    const weekLabels = ['월', '화', '수', '목', '금', '토', '일'];
    final interval = (maxV / 4).clamp(1.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('카테고리별 경고·위험 추이',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                _toggleChip('일별', !_weeklyView, () => setState(() => _weeklyView = false)),
                _toggleChip('주별', _weeklyView, () => setState(() => _weeklyView = true)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 200,
          padding: const EdgeInsets.fromLTRB(4, 14, 12, 8),
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
          child: lines.isEmpty
              ? Center(
                  child: Text('수집된 경고/위험이 아직 없어요.',
                      style: TextStyle(color: Colors.grey[400])))
              : LineChart(LineChartData(
                  minX: 0,
                  maxX: (slots - 1).toDouble(),
                  minY: 0,
                  maxY: maxV.toDouble(),
                  lineBarsData: lines,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: interval,
                        getTitlesWidget: (v, _) {
                          if (v == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text('${v.toInt()}',
                                style: TextStyle(
                                    fontSize: 9, color: Colors.grey[500])),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 20,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (_weeklyView) {
                            if (i < 0 || i >= 7) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                weekLabels[i],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: i == lastIdx ? kGreen : Colors.grey[500],
                                  fontWeight: i == lastIdx
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            );
                          } else {
                            // 시간별: 00, 06, 12, 18, 23만 표시
                            if (![0, 6, 12, 18, 23].contains(i)) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: TextStyle(
                                    fontSize: 9, color: Colors.grey[500]),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  lineTouchData: const LineTouchData(enabled: false),
                )),
        ),
        const SizedBox(height: 10),
        _legend(),
      ],
    );
  }

  Widget _legend() {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final c in _chartCategories)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: _categoryColor(c), shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text('${_categoryEmoji(c)} ${_categoryLabel(c)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          ]),
      ],
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? Colors.white : Colors.grey,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
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
      AppCategory.study => '학습',
      AppCategory.other => '기타',
    };

Color _categoryColor(AppCategory c) => switch (c) {
      AppCategory.video => const Color(0xFFE53935),
      AppCategory.game => const Color(0xFF8E24AA),
      AppCategory.social => const Color(0xFF1E88E5),
      AppCategory.study => const Color(0xFF00897B),
      AppCategory.other => const Color(0xFF757575),
    };

