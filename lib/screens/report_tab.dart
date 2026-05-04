import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/posture_state.dart';
import '../models/posture_snapshot.dart';
import '../painters/arc_gauge_painter.dart';

class ReportTab extends StatefulWidget {
  final PostureState          data;
  final List<PostureSnapshot> snapshots;
  final int                   todayScore;

  const ReportTab({
    super.key,
    required this.data,
    required this.snapshots,
    required this.todayScore,
  });

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  bool _weeklyView   = false;
  bool _monthlyComp  = false;

  // 오늘 평균 목 각도
  double get _avgPitchDeg {
    if (widget.snapshots.isEmpty) return 0;
    return widget.snapshots.map((s) => s.pitchDeg).reduce((a, b) => a + b) /
        widget.snapshots.length;
  }

  // 현재 목 각도
  double get _currentPitchDeg =>
      (1.0 - (widget.data.scores['pitch'] ?? 1.0)) * 20.0;

  // 이전 점수 (스냅샷 전반부 평균)
  int get _prevScore {
    if (widget.snapshots.length < 2) return 0;
    final half = widget.snapshots.sublist(0, widget.snapshots.length ~/ 2);
    return (half.map((s) => s.score).reduce((a, b) => a + b) / half.length)
        .round();
  }

  int get _scoreDiff => widget.todayScore - _prevScore;

  String get _motivationalText {
    final s = widget.todayScore;
    if (s == 0)  return '측정 데이터가 없습니다. 잠시 후 자동으로 측정됩니다.';
    if (s > 90)  return '완벽합니다! 상위 5%에 해당하는 자세 점수입니다.';
    if (s > 75)  return '훌륭합니다! 상위 15%에 해당하는 자세 점수입니다.';
    if (s > 60)  return '평균입니다. 꾸준한 자세 관리가 필요합니다.';
    if (s > 40)  return '주의가 필요합니다. 자세 교정을 권장합니다.';
    return '위험합니다! 즉각적인 스트레칭이 필요합니다.';
  }

  String get _percentileText {
    final s = widget.todayScore;
    if (s > 90) return '상위 5%';
    if (s > 75) return '상위 15%';
    if (s > 60) return '상위 40%';
    if (s > 40) return '하위 40%';
    return '하위 20%';
  }

  String get _pitchAdvice {
    final deg = _avgPitchDeg;
    if (deg < 10) return '목 각도가 양호합니다. 현재 자세를 유지하세요.';
    if (deg < 20) return '목이 약간 앞으로 기울어져 있습니다.\n주기적인 스트레칭이 필요합니다.';
    return '목 각도가 위험 수준입니다!\n즉각적인 자세 교정이 필요합니다.';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  // 왼쪽 열
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _scoreGaugeCard()),
                        const SizedBox(height: 12),
                        Expanded(child: _biometricCard()),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 오른쪽 열
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _timelineCard()),
                        const SizedBox(height: 12),
                        Expanded(child: _comparisonCard()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 70), // 바텀 네비 공간
        ],
      ),
    );
  }

  // ── 상단 헤더 ────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Text('자세 분석 리포트',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(
            '${widget.snapshots.length}회 측정',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ── 카드 1: 오늘의 자세 건강 점수 ────────────────────────────────
  Widget _scoreGaugeCard() {
    final score = widget.todayScore;
    final ratio = score / 100.0;
    final percentile = _percentileText;

    return _card(
      title: '오늘의 자세 건강 점수',
      subtitle: 'DAILY HEALTH SCORE',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                width: 150, height: 150,
                child: CustomPaint(
                  painter: ArcGaugePainter(
                    ratio: ratio,
                    strokeWidth: 14,
                    color: kGreen,
                    trackColor: const Color(0xFFE8F8F3),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$score',
                        style: const TextStyle(
                          fontSize: 42, fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text('POINTS',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey,
                              letterSpacing: 1.5)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                children: [
                  TextSpan(text: _motivationalText.replaceFirst(
                      percentile, '')),
                  TextSpan(
                    text: percentile,
                    style: const TextStyle(
                        color: kGreen, fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: '에 해당하는 자세 점수입니다.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 카드 2: 시간대별 자세 변화 ────────────────────────────────────
  Widget _timelineCard() {
    return _card(
      title: '시간대별 자세 변화',
      subtitle: 'TIMELINE TREND',
      trailing: _toggleRow(
        ['일별', '주별'], _weeklyView ? 1 : 0,
        (i) => setState(() => _weeklyView = i == 1),
      ),
      child: Column(
        children: [
          Expanded(
            child: widget.snapshots.length < 2
                ? Center(
                    child: Text('측정 데이터 수집 중...',
                        style: TextStyle(color: Colors.grey[400])))
                : CustomPaint(
                    painter: _TimelineGraphPainter(
                        snapshots: widget.snapshots),
                  ),
          ),
          if (widget.snapshots.length >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                _timelineInsight(),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
        ],
      ),
    );
  }

  String _timelineInsight() {
    if (widget.snapshots.length < 2) return '';
    int minIdx = 0;
    for (int i = 1; i < widget.snapshots.length; i++) {
      if (widget.snapshots[i].score < widget.snapshots[minIdx].score) {
        minIdx = i;
      }
    }
    final t  = widget.snapshots[minIdx].time;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '* $hh:$mm경 자세가 가장 많이 흐트러집니다.';
  }

  // ── 카드 3: 신체 하중 및 각도 분석 ──────────────────────────────
  Widget _biometricCard() {
    final curr = _currentPitchDeg;
    final avg  = _avgPitchDeg;
    final currColor = curr > 20 ? Colors.red : curr > 10 ? Colors.orange : kGreen;
    final avgColor  = avg  > 20 ? Colors.red : avg  > 10 ? Colors.blue   : kGreen;

    return _card(
      title: '신체 하중 및 각도 분석',
      subtitle: 'BIOMETRIC DATA',
      child: Row(
        children: [
          // 사람 그림
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CustomPaint(
                painter: _BodyFigurePainter(angleDeg: curr),
              ),
            ),
          ),
          // 수치
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('현재 목 각도',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      '${curr.toStringAsFixed(1)}°',
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold,
                          color: currColor),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('Forward',
                          style: TextStyle(fontSize: 11, color: currColor)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('하루 평균 각도',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      '${avg.toStringAsFixed(1)}°',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold,
                          color: avgColor),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('Average',
                          style: TextStyle(fontSize: 11, color: avgColor)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    _pitchAdvice,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 카드 4: 지난 대비 개선도 ──────────────────────────────────────
  Widget _comparisonCard() {
    final prev = _prevScore;
    final curr = widget.todayScore;
    final diff = _scoreDiff;
    final improved = diff >= 0;

    return _card(
      title: '이전 대비 개선도',
      subtitle: 'PROGRESS COMPARISON',
      trailing: _toggleRow(
        ['주간', '월간'], _monthlyComp ? 1 : 0,
        (i) => setState(() => _monthlyComp = i == 1),
      ),
      child: Column(
        children: [
          Expanded(
            child: prev == 0
                ? Center(
                    child: Text('비교할 데이터가 부족합니다.',
                        style: TextStyle(color: Colors.grey[400])))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: CustomPaint(
                      painter: _BarChartPainter(
                        prevScore: prev, currScore: curr,
                      ),
                    ),
                  ),
          ),
          if (prev > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                Icon(
                  improved ? Icons.arrow_upward : Icons.arrow_downward,
                  color: improved ? kGreen : Colors.red, size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '${improved ? '+' : ''}$diff점 ${improved ? '상승' : '하락'}',
                  style: TextStyle(
                    color: improved ? kGreen : Colors.red,
                    fontWeight: FontWeight.bold, fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text('달성 목표 관리 중',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ]),
            ),
        ],
      ),
    );
  }

  // ── 공통 카드 컨테이너 ────────────────────────────────────────────
  Widget _card({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[400],
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
                if (trailing case final t?) t,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _toggleRow(List<String> labels, int selected, void Function(int) onSelect) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active ? kGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  color: active ? Colors.white : Colors.grey,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── CustomPainter: 시간대별 그래프 ──────────────────────────────────
class _TimelineGraphPainter extends CustomPainter {
  final List<PostureSnapshot> snapshots;
  const _TimelineGraphPainter({required this.snapshots});

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.length < 2) return;

    const pad = 28.0;
    final w   = size.width  - pad * 2;
    final h   = size.height - pad - 20;

    final scores  = snapshots.map((s) => s.score.toDouble()).toList();
    final minS    = scores.reduce((a, b) => a < b ? a : b).clamp(0, 100).toDouble();
    final maxS    = scores.reduce((a, b) => a > b ? a : b).clamp(0, 100).toDouble();
    final range   = (maxS - minS).clamp(10, 100).toDouble();
    final n       = snapshots.length;
    final step    = w / (n - 1);

    double xOf(int i) => pad + i * step;
    double yOf(int i) => pad + h * (1 - (scores[i] - minS) / range);

    // 면적 채움
    final fillPath = Path()
      ..moveTo(xOf(0), size.height - 20)
      ..lineTo(xOf(0), yOf(0));
    for (int i = 1; i < n; i++) { fillPath.lineTo(xOf(i), yOf(i)); }
    fillPath
      ..lineTo(xOf(n - 1), size.height - 20)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = kGreen.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    // 선
    final linePath = Path()..moveTo(xOf(0), yOf(0));
    for (int i = 1; i < n; i++) { linePath.lineTo(xOf(i), yOf(i)); }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = kGreen
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < n; i++) {
      final x = xOf(i);
      final y = yOf(i);

      // 점
      canvas.drawCircle(Offset(x, y), 4,
          Paint()..color = kGreen..style = PaintingStyle.fill);

      // 점수 라벨
      tp.text = TextSpan(
        text: '${scores[i].toInt()}',
        style: const TextStyle(fontSize: 10, color: kGreen,
            fontWeight: FontWeight.bold),
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - 16));

      // 시간 라벨 (2개마다 또는 처음·끝)
      if (i == 0 || i == n - 1 || (n <= 6) || (i % (n ~/ 4) == 0)) {
        final t  = snapshots[i].time;
        final hh = t.hour.toString().padLeft(2, '0');
        final mm = t.minute.toString().padLeft(2, '0');
        tp.text = TextSpan(
          text: '$hh:$mm',
          style: TextStyle(fontSize: 9, color: Colors.grey[400]),
        );
        tp.layout();
        tp.paint(canvas,
            Offset(x - tp.width / 2, size.height - 18));
      }
    }
  }

  @override
  bool shouldRepaint(_TimelineGraphPainter old) =>
      old.snapshots.length != snapshots.length;
}

// ── CustomPainter: 비교 바 차트 ──────────────────────────────────────
class _BarChartPainter extends CustomPainter {
  final int prevScore;
  final int currScore;
  const _BarChartPainter({required this.prevScore, required this.currScore});

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 28.0;
    final maxH   = size.height - labelH * 2;
    final barW   = size.width * 0.28;
    final gap    = (size.width - barW * 2) / 3;

    final maxVal = [prevScore, currScore, 1].reduce((a, b) => a > b ? a : b);

    void drawBar(double x, int score, Color color, String label, bool top) {
      final barH  = maxH * (score / maxVal);
      final top0  = maxH - barH + labelH;
      final rect  = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top0, barW, barH),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, Paint()..color = color);

      final tp = TextPainter(textDirection: TextDirection.ltr);

      // 수치 (바 위)
      tp.text = TextSpan(
        text: '$score',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
      );
      tp.layout();
      tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, top0 - 20));

      // 라벨 (바 아래)
      tp.text = TextSpan(
        text: label,
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      );
      tp.layout();
      tp.paint(canvas,
          Offset(x + barW / 2 - tp.width / 2, size.height - labelH + 6));
    }

    drawBar(gap,           prevScore, Colors.grey[300]!, '이전',  false);
    drawBar(gap * 2 + barW, currScore, kGreen,           '현재', true);
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.prevScore != prevScore || old.currScore != currScore;
}

// ── CustomPainter: 사람 실루엣 + 목 각도 ─────────────────────────────
class _BodyFigurePainter extends CustomPainter {
  final double angleDeg;
  const _BodyFigurePainter({required this.angleDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.fill;

    final cx       = size.width  * 0.5;
    final bodyW    = size.width  * 0.32;
    final bodyTop  = size.height * 0.38;
    final bodyBot  = size.height * 0.92;
    final headR    = size.width  * 0.14;

    // 몸통
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - bodyW / 2, bodyTop, bodyW, bodyBot - bodyTop),
        Radius.circular(bodyW / 3),
      ),
      bodyPaint,
    );

    // 머리 (앞으로 기울기 표현)
    final maxOffset = size.width * 0.18;
    final offset    = (angleDeg / 30.0).clamp(0.0, 1.0) * maxOffset;
    final headX     = cx + offset;
    final headY     = bodyTop - headR * 0.6;

    canvas.drawCircle(
      Offset(headX, headY), headR,
      Paint()..color = Colors.grey[400]!..style = PaintingStyle.fill,
    );

    // 목 선
    canvas.drawLine(
      Offset(cx, bodyTop),
      Offset(headX, headY + headR),
      Paint()..color = Colors.grey[350]!..strokeWidth = bodyW * 0.4
          ..strokeCap = StrokeCap.round,
    );

    // 각도 호 (빨간색)
    if (angleDeg > 1) {
      final arcRect = Rect.fromCircle(
          center: Offset(cx, bodyTop), radius: size.width * 0.22);
      canvas.drawArc(
        arcRect, -1.57, (angleDeg / 30.0).clamp(0.0, 1.0) * 0.8,
        false,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.7)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_BodyFigurePainter old) => old.angleDeg != angleDeg;
}
