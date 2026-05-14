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
  bool _weeklyView  = false;
  bool _monthlyComp = false;

  double get _avgPitchDeg {
    if (widget.snapshots.isEmpty) return 0;
    return widget.snapshots.map((s) => s.pitchDeg).reduce((a, b) => a + b) /
        widget.snapshots.length;
  }

  double get _currentPitchDeg =>
      (1.0 - (widget.data.scores['pitch'] ?? 1.0)) * 20.0;

  int get _prevScore {
    if (widget.snapshots.length < 2) return 0;
    final half = widget.snapshots.sublist(0, widget.snapshots.length ~/ 2);
    return (half.map((s) => s.score).reduce((a, b) => a + b) / half.length)
        .round();
  }

  int get _scoreDiff => widget.todayScore - _prevScore;

  String get _motivationalText {
    final s = widget.todayScore;
    if (s == 0) return '측정 데이터가 없습니다. 잠시 후 자동으로 측정됩니다.';
    if (s > 90) return '완벽합니다! 상위 5%에 해당하는 자세 점수입니다.';
    if (s > 75) return '훌륭합니다! 상위 15%에 해당하는 자세 점수입니다.';
    if (s > 60) return '평균입니다. 꾸준한 자세 관리가 필요합니다.';
    if (s > 40) return '주의가 필요합니다. 자세 교정을 권장합니다.';
    return '위험합니다! 즉각적인 스트레칭이 필요합니다.';
  }

  String get _pitchAdvice {
    final deg = _avgPitchDeg;
    if (deg < 10) return '목 각도 양호 — 현재 자세를 유지하세요.';
    if (deg < 20) return '목이 약간 앞으로 기울어져 있습니다. 스트레칭 필요.';
    return '목 각도 위험 수준! 즉각적인 자세 교정이 필요합니다.';
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.todayScore;
    final ratio = score / 100.0;
    final curr  = _currentPitchDeg;
    final avg   = _avgPitchDeg;
    final diff  = _scoreDiff;
    final prev  = _prevScore;
    final improved = diff >= 0;

    final currColor = curr > 15 ? Colors.red : curr > 8 ? Colors.orange : kGreen;
    final avgColor  = avg  > 15 ? Colors.red : avg  > 8 ? Colors.blue   : kGreen;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── 헤더 ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('자세 분석 리포트',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('${widget.snapshots.length}회 측정',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── 카드 1: 점수 게이지 ──────────────────────────────
                _card(
                  title: '오늘의 자세 건강 점수',
                  subtitle: 'DAILY HEALTH SCORE',
                  child: Column(children: [
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 160, height: 160,
                      child: CustomPaint(
                        painter: ArcGaugePainter(
                          ratio: ratio, strokeWidth: 16,
                          color: kGreen,
                          trackColor: const Color(0xFFE8F8F3),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$score',
                                style: const TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.bold)),
                            const Text('POINTS',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                    letterSpacing: 2)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(_motivationalText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 12),
                  ]),
                ),
                const SizedBox(height: 12),

                // ── 카드 2: 목 각도 분석 ─────────────────────────────
                _card(
                  title: '목 각도 분석',
                  subtitle: 'NECK ANGLE',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      // 거북목 기준 설명
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('거북목 기준',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                            SizedBox(height: 6),
                            _AngleRow(label: '0° ~ 8°',  desc: '정상',  color: kGreen),
                            _AngleRow(label: '8° ~ 15°', desc: '주의',  color: Colors.orange),
                            _AngleRow(label: '15° 이상', desc: '거북목', color: Colors.red),
                          ],
                        ),
                      ),
                      // 현재 / 평균
                      Row(children: [
                        Expanded(child: _metricBox(
                          '현재 목 각도',
                          '${curr.toStringAsFixed(1)}°',
                          'Forward',
                          currColor,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _metricBox(
                          '하루 평균 각도',
                          '${avg.toStringAsFixed(1)}°',
                          'Average',
                          avgColor,
                        )),
                      ]),
                      const SizedBox(height: 12),
                      // 각도 게이지 바
                      _angleBar(curr, '현재', currColor),
                      const SizedBox(height: 8),
                      _angleBar(avg,  '평균', avgColor),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: currColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_pitchAdvice,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[700])),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // ── 카드 3: 시간대별 변화 ────────────────────────────
                _card(
                  title: '시간대별 자세 변화',
                  subtitle: 'TIMELINE TREND',
                  trailing: _toggleRow(
                    ['일별', '주별'], _weeklyView ? 1 : 0,
                    (i) => setState(() => _weeklyView = i == 1),
                  ),
                  child: SizedBox(
                    height: 160,
                    child: widget.snapshots.length < 2
                        ? Center(
                            child: Text('측정 데이터 수집 중...',
                                style: TextStyle(color: Colors.grey[400])))
                        : CustomPaint(
                            painter: _TimelinePainter(
                                snapshots: widget.snapshots),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── 카드 4: 이전 대비 개선도 ─────────────────────────
                _card(
                  title: '이전 대비 개선도',
                  subtitle: 'PROGRESS COMPARISON',
                  trailing: _toggleRow(
                    ['주간', '월간'], _monthlyComp ? 1 : 0,
                    (i) => setState(() => _monthlyComp = i == 1),
                  ),
                  child: prev == 0
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                              child: Text('비교할 데이터가 부족합니다.',
                                  style: TextStyle(color: Colors.grey[400]))),
                        )
                      : Column(children: [
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 120,
                            child: CustomPaint(
                              painter: _BarChartPainter(
                                  prevScore: prev,
                                  currScore: widget.todayScore),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Icon(
                              improved
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              color: improved ? kGreen : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${improved ? '+' : ''}$diff점 ${improved ? '상승' : '하락'}',
                              style: TextStyle(
                                color: improved ? kGreen : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            Text('달성 목표 관리 중',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500])),
                          ]),
                          const SizedBox(height: 8),
                        ]),
                ),

                // ── 카드 5: 세부 지표 ─────────────────────────────────
                const SizedBox(height: 12),
                _card(
                  title: '세부 지표',
                  subtitle: 'SUB SCORES',
                  child: Column(children: [
                    _subBar('머리 피치',   widget.data.scores['pitch'] ?? 1.0),
                    _subBar('눈-어깨 비율', widget.data.scores['eye']   ?? 1.0),
                    _subBar('귀 가시성',   widget.data.scores['vis']   ?? 1.0),
                    _subBar('Z축 보조',    widget.data.scores['z']     ?? 1.0,
                        last: true),
                  ]),
                ),

              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── 공통 카드 컨테이너 ──────────────────────────────────────────
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
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: TextStyle(
                      fontSize: 10, color: Colors.grey[400],
                      letterSpacing: 0.5)),
                ],
              )),
              ?trailing,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: child,
        ),
      ]),
    );
  }

  Widget _metricBox(String label, String value, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text(value, style: TextStyle(
            fontSize: 26, fontWeight: FontWeight.bold, color: color)),
        Text(sub, style: TextStyle(fontSize: 11, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(
            fontSize: 11, color: Colors.grey[600])),
      ]),
    );
  }

  Widget _angleBar(double deg, String label, Color color) {
    const maxDeg = 30.0;
    final ratio = (deg / maxDeg).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        Text('${deg.toStringAsFixed(1)}°',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ]),
      const SizedBox(height: 4),
      // LinearProgressIndicator 사용 - Stack/FractionallySizedBox 충돌 방지
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 8,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
      // 거북목 기준선 표시 (15° = 50%)
      LayoutBuilder(builder: (ctx, constraints) {
        final markerX = constraints.maxWidth * (15 / maxDeg);
        return SizedBox(
          height: 12,
          child: Stack(children: [
            Positioned(
              left: markerX - 1,
              child: Container(
                width: 2, height: 12,
                color: Colors.orange.withValues(alpha: 0.6),
              ),
            ),
            Positioned(
              left: markerX + 4,
              child: Text('15°',
                  style: TextStyle(fontSize: 9, color: Colors.orange[700])),
            ),
          ]),
        );
      }),
    ]);
  }

  Widget _subBar(String label, double value, {bool last = false}) {
    final col = value > 0.65 ? kGreen
        : value > 0.40 ? Colors.orange : Colors.red;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text('${(value * 100).clamp(0, 100).toInt()}',
              style: TextStyle(fontWeight: FontWeight.bold, color: col)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(col),
          ),
        ),
      ]),
    );
  }

  Widget _toggleRow(List<String> labels, int selected,
      void Function(int) onSelect) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < labels.length; i++)
          GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: i == selected ? kGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(labels[i], style: TextStyle(
                fontSize: 11,
                color: i == selected ? Colors.white : Colors.grey,
                fontWeight: i == selected
                    ? FontWeight.w700 : FontWeight.normal,
              )),
            ),
          ),
      ]),
    );
  }
}

// ── 각도 기준 행 ──────────────────────────────────────────────────
class _AngleRow extends StatelessWidget {
  final String label;
  final String desc;
  final Color  color;

  const _AngleRow({
    required this.label,
    required this.desc,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Text('→ $desc',
            style: TextStyle(fontSize: 12, color: color,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

// ── 타임라인 그래프 ───────────────────────────────────────────────
class _TimelinePainter extends CustomPainter {
  final List<PostureSnapshot> snapshots;
  const _TimelinePainter({required this.snapshots});

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.length < 2) return;
    const pad = 24.0;
    final w = size.width - pad;
    final h = size.height - pad - 16;
    final n = snapshots.length;
    final scores = snapshots.map((s) => s.score.toDouble()).toList();
    final minS = scores.reduce((a, b) => a < b ? a : b);
    final maxS = scores.reduce((a, b) => a > b ? a : b);
    final range = (maxS - minS).clamp(10.0, 100.0);

    double xOf(int i) => pad + (i / (n - 1)) * w;
    double yOf(int i) => 8 + h * (1 - (scores[i] - minS) / range);

    // 면적
    final fill = Path()
      ..moveTo(xOf(0), size.height - 16)
      ..lineTo(xOf(0), yOf(0));
    for (int i = 1; i < n; i++) { fill.lineTo(xOf(i), yOf(i)); }
    fill..lineTo(xOf(n - 1), size.height - 16)..close();
    canvas.drawPath(fill,
        Paint()..color = kGreen.withValues(alpha: 0.12)
               ..style = PaintingStyle.fill);

    // 선
    final line = Path()..moveTo(xOf(0), yOf(0));
    for (int i = 1; i < n; i++) { line.lineTo(xOf(i), yOf(i)); }
    canvas.drawPath(line,
        Paint()..color = kGreen..strokeWidth = 2
               ..style = PaintingStyle.stroke
               ..strokeCap = StrokeCap.round
               ..strokeJoin = StrokeJoin.round);

    final tp = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < n; i++) {
      canvas.drawCircle(Offset(xOf(i), yOf(i)), 4,
          Paint()..color = kGreen..style = PaintingStyle.fill);

      // 점수
      tp.text = TextSpan(text: '${scores[i].toInt()}',
          style: const TextStyle(fontSize: 9, color: kGreen,
              fontWeight: FontWeight.bold));
      tp.layout();
      tp.paint(canvas, Offset(xOf(i) - tp.width / 2, yOf(i) - 16));

      // 시간
      if (i == 0 || i == n - 1 || (n <= 5) || i % ((n - 1) ~/ 3 + 1) == 0) {
        final t = snapshots[i].time;
        tp.text = TextSpan(
            text: '${t.hour.toString().padLeft(2,'0')}:'
                  '${t.minute.toString().padLeft(2,'0')}',
            style: TextStyle(fontSize: 9, color: Colors.grey[400]));
        tp.layout();
        tp.paint(canvas,
            Offset(xOf(i) - tp.width / 2, size.height - 14));
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.snapshots.length != snapshots.length;
}

// ── 바 차트 ───────────────────────────────────────────────────────
class _BarChartPainter extends CustomPainter {
  final int prevScore;
  final int currScore;
  const _BarChartPainter({required this.prevScore, required this.currScore});

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 24.0;
    final maxH   = size.height - labelH * 2;
    final barW   = size.width * 0.28;
    final gap    = (size.width - barW * 2) / 3;
    final maxVal = [prevScore, currScore, 1].reduce((a, b) => a > b ? a : b);

    void drawBar(double x, int s, Color col, String lbl) {
      final barH = maxH * (s / maxVal);
      final top  = maxH - barH + labelH;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top, barW, barH), const Radius.circular(6)),
        Paint()..color = col,
      );
      final tp = TextPainter(textDirection: TextDirection.ltr);
      tp.text = TextSpan(text: '$s',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
              color: col));
      tp.layout();
      tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, top - 20));

      tp.text = TextSpan(text: lbl,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]));
      tp.layout();
      tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2,
          size.height - labelH + 4));
    }

    drawBar(gap,            prevScore, Colors.grey[300]!, '이전');
    drawBar(gap * 2 + barW, currScore, kGreen,           '현재');
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.prevScore != prevScore || old.currScore != currScore;
}
