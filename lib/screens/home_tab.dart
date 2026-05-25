import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/app_usage_record.dart';
import '../services/app_category_classifier.dart';
import '../services/usage_tracker_service.dart';

class HomeTab extends StatefulWidget {
  final bool connected;

  const HomeTab({super.key, required this.connected});

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('안녕하세요!',
              style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const Text('포스처가드',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.connected ? kGreen : Colors.redAccent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.connected ? '연결됨' : '연결 중',
            style: TextStyle(
              fontSize: 12,
              color: widget.connected ? kGreen : Colors.redAccent,
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildTopAppCard() {
    final top = UsageTrackerService.instance.topAppToday();
    final hasData = top != null && top.usageSeconds > 0;

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
          const Text('오늘 가장 많이 쓴 앱',
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
            Expanded(child: _miniStat('주의·위험', '${top.warningCount}회')),
            const SizedBox(width: 10),
            Expanded(child: _miniStat('시간당 주의+경고',
                top.usageSeconds == 0
                    ? '—'
                    : '${(top.warningCount / (top.usageSeconds / 3600)).toStringAsFixed(1)}회')),
          ]),
        ]),
      ),
    ]);
  }

  Widget _topAppEmptyContent() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('오늘 가장 많이 쓴 앱',
          style: TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: 16),
      Text(
        '아직 측정된 앱 사용 기록이 없어요.\n잠시 후 자동으로 집계됩니다.',
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
    final data = _weeklyView
        ? tracker.weeklyByCategory()
        : tracker.hourlyByCategoryToday();
    final lastIdx = _weeklyView ? tracker.todayWeekdayIndex() : tracker.todayHourIndex();
    final hasAnyData = data.values.any((list) {
      for (int i = 0; i <= lastIdx; i++) {
        if (list[i] > 0) return true;
      }
      return false;
    });

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
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
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
          child: hasAnyData
              ? CustomPaint(
                  painter: _CategoryLinePainter(
                    data: data,
                    categories: _chartCategories,
                    lastIndex: lastIdx,
                    weekly: _weeklyView,
                  ),
                  child: Container(),
                )
              : Center(
                  child: Text('수집된 경고/위험이 아직 없어요.',
                      style: TextStyle(color: Colors.grey[400]))),
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

class _CategoryLinePainter extends CustomPainter {
  final Map<AppCategory, List<int>> data;
  final List<AppCategory> categories;
  final int lastIndex; // 이 인덱스까지만 선을 그림
  final bool weekly;

  _CategoryLinePainter({
    required this.data,
    required this.categories,
    required this.lastIndex,
    required this.weekly,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 28.0;
    const rightPad = 8.0;
    const topPad = 8.0;
    const bottomPad = 22.0;
    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;
    final slots = weekly ? 7 : 24;
    final maxIdx = lastIndex.clamp(0, slots - 1);

    int maxVal = 0;
    for (final c in categories) {
      final list = data[c];
      if (list == null) continue;
      for (int i = 0; i <= maxIdx; i++) {
        if (list[i] > maxVal) maxVal = list[i];
      }
    }
    if (maxVal < 4) maxVal = 4; // 최소 눈금

    final tp = TextPainter(textDirection: TextDirection.ltr);

    // y 보조선 + 라벨 (0, max/2, max)
    final yLineP = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    for (final yv in [0, maxVal ~/ 2, maxVal]) {
      final y = topPad + plotH * (1 - yv / maxVal);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), yLineP);
      tp.text = TextSpan(
        text: '$yv',
        style: TextStyle(fontSize: 9, color: Colors.grey[500]),
      );
      tp.layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    double xOf(int i) {
      if (slots == 1) return leftPad + plotW / 2;
      return leftPad + plotW * (i / (slots - 1));
    }

    double yOf(int v) => topPad + plotH * (1 - v / maxVal);

    // x 라벨
    if (weekly) {
      const labels = ['월', '화', '수', '목', '금', '토', '일'];
      for (int i = 0; i < 7; i++) {
        tp.text = TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 10,
            color: i == maxIdx ? kGreen : Colors.grey[500],
            fontWeight: i == maxIdx ? FontWeight.bold : FontWeight.normal,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(xOf(i) - tp.width / 2, size.height - bottomPad + 4));
      }
    } else {
      for (final h in [0, 6, 12, 18, 23]) {
        tp.text = TextSpan(
          text: h.toString().padLeft(2, '0'),
          style: TextStyle(fontSize: 9, color: Colors.grey[500]),
        );
        tp.layout();
        tp.paint(canvas, Offset(xOf(h) - tp.width / 2, size.height - bottomPad + 4));
      }
    }

    // 카테고리별 선
    for (final c in categories) {
      final list = data[c];
      if (list == null) continue;
      final color = _categoryColor(c);
      final path = Path();
      bool started = false;
      for (int i = 0; i <= maxIdx; i++) {
        final v = list[i];
        final x = xOf(i);
        final y = yOf(v);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // 점
      for (int i = 0; i <= maxIdx; i++) {
        final v = list[i];
        if (v == 0) continue;
        canvas.drawCircle(
          Offset(xOf(i), yOf(v)),
          2.5,
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CategoryLinePainter old) =>
      old.weekly != weekly ||
      old.lastIndex != lastIndex ||
      old.data != data;
}
