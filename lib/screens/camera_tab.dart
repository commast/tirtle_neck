import 'dart:async';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/posture_snapshot.dart';
import '../painters/arc_gauge_painter.dart';

/// 카메라 탭 — 실시간 스트리밍 없음
/// 시작 버튼 → 즉시 1회 촬영 → 2분마다 자동 반복
/// 다른 탭으로 이동해도 계속 동작, 중지 버튼 누를 때만 멈춤
class CameraTab extends StatefulWidget {
  final bool                  captureActive;
  final List<PostureSnapshot> captureHistory;
  final DateTime?             lastCaptureTime;
  final bool                  connected;
  final Future<void> Function() onStart;
  final VoidCallback          onStop;

  const CameraTab({
    super.key,
    required this.captureActive,
    required this.captureHistory,
    required this.lastCaptureTime,
    required this.connected,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab>
    with SingleTickerProviderStateMixin {
  Timer?            _countdownTimer;
  int               _secondsLeft = 120;
  late AnimationController _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    if (widget.captureActive) _startCountdown();
  }

  @override
  void didUpdateWidget(CameraTab old) {
    super.didUpdateWidget(old);
    if (!old.captureActive && widget.captureActive) {
      _secondsLeft = 120;
      _startCountdown();
    }
    if (old.captureActive && !widget.captureActive) {
      _countdownTimer?.cancel();
    }
    // 새 캡처 완료 → 카운트다운 리셋
    if (widget.captureHistory.length > old.captureHistory.length) {
      setState(() => _secondsLeft = 120);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft = _secondsLeft > 0 ? _secondsLeft - 1 : 120);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseAnim.dispose();
    super.dispose();
  }

  String get _countdown {
    final m = _secondsLeft ~/ 60;
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final history  = widget.captureHistory;
    final score    = history.isNotEmpty ? history.last.score : 0;
    final ratio    = score / 100.0;
    final scoreCol = score > 65 ? kGreen
        : score > 40 ? Colors.orange : Colors.red;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),

                // ── 헤더 ────────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('자세 측정',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  _connChip(),
                ]),
                const SizedBox(height: 20),

                // ── 상태 카드 ────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12, offset: const Offset(0, 4),
                    )],
                  ),
                  child: Column(children: [
                    // 측정 상태 표시
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (widget.captureActive) ...[
                        FadeTransition(
                          opacity: _pulseAnim,
                          child: Container(width: 12, height: 12,
                              decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle)),
                        ),
                        const SizedBox(width: 8),
                        const Text('측정 중',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16, color: Colors.red)),
                      ] else ...[
                        Container(width: 12, height: 12,
                            decoration: BoxDecoration(
                                color: Colors.grey[300],
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text('정지됨',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16, color: Colors.grey[500])),
                      ],
                    ]),
                    const SizedBox(height: 20),

                    // 점수 게이지
                    SizedBox(width: 140, height: 140,
                      child: CustomPaint(
                        painter: ArcGaugePainter(
                          ratio: ratio, strokeWidth: 14,
                          color: history.isEmpty ? Colors.grey[300]! : scoreCol,
                          trackColor: const Color(0xFFEEEEEE),
                        ),
                        child: Center(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              history.isEmpty ? '-' : '$score',
                              style: TextStyle(
                                  fontSize: 40, fontWeight: FontWeight.bold,
                                  color: history.isEmpty
                                      ? Colors.grey[400] : scoreCol),
                            ),
                            Text('점', style: TextStyle(
                                fontSize: 13, color: Colors.grey[500])),
                          ],
                        )),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (history.isNotEmpty)
                      Text(
                        '마지막 측정: ${_fmt(history.last.time)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),

                    if (widget.captureActive) ...[
                      const SizedBox(height: 4),
                      Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.timer_outlined,
                            size: 14, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text('다음 촬영까지 $_countdown',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      ]),
                    ],
                    const SizedBox(height: 20),

                    // 시작 / 중지 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: !widget.connected ? null
                            : widget.captureActive
                                ? widget.onStop
                                : () => widget.onStart(),
                        icon: Icon(widget.captureActive
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded),
                        label: Text(widget.captureActive
                            ? '측정 중지'
                            : widget.connected ? '측정 시작'
                                : '서버 연결 필요'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              widget.captureActive ? Colors.red : kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── 점수 그래프 ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05), blurRadius: 8,
                    )],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Row(children: [
                      const Text('점수 기록',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('총 ${history.length}회',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: history.length < 2
                          ? Center(child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.show_chart_rounded,
                                    size: 40, color: Colors.grey[300]),
                                const SizedBox(height: 8),
                                Text(
                                  widget.captureActive
                                      ? '측정 데이터 수집 중...'
                                      : '측정을 시작하면 그래프가 표시됩니다.',
                                  style: TextStyle(
                                      color: Colors.grey[400], fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ))
                          : CustomPaint(
                              painter: _GraphPainter(history: history),
                            ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── 측정 기록 목록 ────────────────────────────────────
                if (history.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                      )],
                    ),
                    child: Column(children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('측정 기록',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: history.length,
                        separatorBuilder: (_, idx) =>
                            const Divider(height: 1, indent: 16),
                        itemBuilder: (ctx, i) {
                          final snap = history[history.length - 1 - i];
                          final col = snap.score > 65 ? kGreen
                              : snap.score > 40 ? Colors.orange : Colors.red;
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              backgroundColor: col.withValues(alpha: 0.12),
                              child: Text('${snap.score}',
                                  style: TextStyle(
                                      color: col,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ),
                            title: Text(_fmt(snap.time),
                                style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              snap.score > 65 ? '자세 양호'
                                  : snap.score > 40 ? '주의 필요'
                                  : '거북목 감지',
                              style: TextStyle(fontSize: 11, color: col),
                            ),
                            trailing: Text(
                              '목 ${snap.pitchDeg.toStringAsFixed(1)}°',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          );
                        },
                      ),
                    ]),
                  ),

                if (widget.captureActive) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kGreen.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: kGreen.withValues(alpha: 0.3)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded,
                          color: kGreen, size: 18),
                      SizedBox(width: 10),
                      Expanded(child: Text(
                        '다른 탭으로 이동하거나 앱을 백그라운드로 보내도\n'
                        '측정은 계속 진행됩니다.',
                        style: TextStyle(fontSize: 12, color: kGreen),
                      )),
                    ]),
                  ),
                ],
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (widget.connected ? kGreen : Colors.red)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.connected ? kGreen : Colors.red)),
        const SizedBox(width: 6),
        Text(widget.connected ? '서버 연결됨' : '서버 끊김',
            style: TextStyle(fontSize: 11,
                color: widget.connected ? kGreen : Colors.red)),
      ]),
    );
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2,'0')}:'
      '${t.minute.toString().padLeft(2,'0')}:'
      '${t.second.toString().padLeft(2,'0')}';
}

// ── 점수 그래프 ──────────────────────────────────────────────────
class _GraphPainter extends CustomPainter {
  final List<PostureSnapshot> history;
  const _GraphPainter({required this.history});

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    const padL = 28.0, padB = 20.0, padT = 16.0;
    final w = size.width - padL;
    final h = size.height - padB - padT;
    final n = history.length;
    final scores = history.map((s) => s.score.toDouble()).toList();
    final minS = scores.reduce((a, b) => a < b ? a : b);
    final maxS = scores.reduce((a, b) => a > b ? a : b);
    final range = (maxS - minS).clamp(10.0, 100.0);

    double xOf(int i) => padL + (i / (n - 1)) * w;
    double yOf(int i) => padT + h * (1 - (scores[i] - minS) / range);

    // 격자
    for (final pct in [0.0, 0.5, 1.0]) {
      final y = padT + h * pct;
      canvas.drawLine(Offset(padL, y), Offset(size.width, y),
          Paint()..color = Colors.grey.withValues(alpha: 0.15)..strokeWidth = 1);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(minS + (maxS - minS) * (1 - pct)).toInt()}',
          style: TextStyle(fontSize: 9, color: Colors.grey[400]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    // 면적 채움
    final fill = Path()
      ..moveTo(xOf(0), size.height - padB)
      ..lineTo(xOf(0), yOf(0));
    for (int i = 1; i < n; i++) { fill.lineTo(xOf(i), yOf(i)); }
    fill..lineTo(xOf(n - 1), size.height - padB)..close();
    canvas.drawPath(fill,
        Paint()..color = kGreen.withValues(alpha: 0.12)
               ..style = PaintingStyle.fill);

    // 선
    final line = Path()..moveTo(xOf(0), yOf(0));
    for (int i = 1; i < n; i++) { line.lineTo(xOf(i), yOf(i)); }
    canvas.drawPath(line,
        Paint()..color = kGreen..strokeWidth = 2.5
               ..style = PaintingStyle.stroke
               ..strokeCap = StrokeCap.round
               ..strokeJoin = StrokeJoin.round);

    // 점 + 라벨
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < n; i++) {
      final col = scores[i] > 65 ? kGreen
          : scores[i] > 40 ? Colors.orange : Colors.red;
      canvas.drawCircle(Offset(xOf(i), yOf(i)), 5,
          Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawCircle(Offset(xOf(i), yOf(i)), 5,
          Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 2);

      tp.text = TextSpan(text: '${scores[i].toInt()}',
          style: TextStyle(fontSize: 9, color: col,
              fontWeight: FontWeight.bold));
      tp.layout();
      tp.paint(canvas, Offset(xOf(i) - tp.width / 2, yOf(i) - 18));

      if (i == 0 || i == n - 1 || n <= 5) {
        final t = history[i].time;
        tp.text = TextSpan(
          text: '${t.hour.toString().padLeft(2,'0')}:'
                '${t.minute.toString().padLeft(2,'0')}',
          style: TextStyle(fontSize: 8, color: Colors.grey[400]),
        );
        tp.layout();
        tp.paint(canvas,
            Offset(xOf(i) - tp.width / 2, size.height - padB + 3));
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.history.length != history.length;
}
