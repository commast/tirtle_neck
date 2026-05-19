import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/posture_state.dart';
import '../models/title_system.dart';
import '../painters/arc_gauge_painter.dart';
import '../painters/area_line_painter.dart';

class HomeTab extends StatefulWidget {
  final PostureState  data;
  final bool          connected;
  final List<double>  scoreHistory;
  final int           todayScore;
  final int           snapshotCount;
  final PostureTitle? currentTitle; // null = 측정 전

  const HomeTab({
    super.key,
    required this.data,
    required this.connected,
    required this.scoreHistory,
    required this.todayScore,
    required this.snapshotCount,
    this.currentTitle,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _weeklyView = false;

  @override
  Widget build(BuildContext context) {
    final score = widget.todayScore;
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
                _buildScoreSummaryCard(score),
                const SizedBox(height: 24),
                _buildGraphSection(),
                const SizedBox(height: 24),
                const Text('자세 이슈',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildIssueCards(),
                const SizedBox(height: 24),
                const Text('전문가 가이드',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildGuideCards(),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarRow() {
    final title = widget.currentTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 칭호 배지 (측정 기록 있을 때만 표시) ─────────────────
        if (title != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: title.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: title.color.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(title.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(title.name,
                  style: TextStyle(
                      fontSize: 12, color: title.color,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 8),
        ],
        Row(
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
          const SizedBox(width: 12),
          Stack(children: [
            Icon(Icons.notifications_outlined, size: 28, color: Colors.grey[700]),
            Positioned(
              right: 2, top: 2,
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Colors.redAccent, shape: BoxShape.circle,
                ),
              ),
            ),
          ]),
        ]),
      ],
    ),   // Row 닫기
    ],   // Column children 닫기
  );   // Column 닫기
  }

  Widget _buildScoreSummaryCard(int score) {
    final ratio       = score / 100.0;
    final statusLabel = ratio > 0.75 ? '좋음' : ratio > 0.5 ? '보통' : '나쁨';

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
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('오늘의 자세 점수',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$score',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 56,
                      fontWeight: FontWeight.bold, height: 1,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8, left: 6),
                    child: Text('점',
                        style: TextStyle(color: Colors.white70, fontSize: 20)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.snapshotCount == 0 ? '측정 전' : statusLabel,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.snapshotCount == 0
                      ? '10분마다 자동 측정'
                      : '${widget.snapshotCount}회 평균',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ]),
            ],
          ),
        ),
        SizedBox(
          width: 90, height: 90,
          child: CustomPaint(
            painter: ArcGaugePainter(
              ratio: ratio, strokeWidth: 9, color: Colors.white,
              trackColor: Colors.white.withValues(alpha: 0.25),
            ),
            child: Center(
              child: Text(
                '${(ratio * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildGraphSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('자세 점수 추이',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                _toggleChip('일별', !_weeklyView,
                    () => setState(() => _weeklyView = false)),
                _toggleChip('주별', _weeklyView,
                    () => setState(() => _weeklyView = true)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 140,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
          child: widget.scoreHistory.length < 2
              ? Center(
                  child: Text('측정 데이터 수집 중...',
                      style: TextStyle(color: Colors.grey[400])))
              : CustomPaint(
                  painter: AreaLinePainter(
                    data: widget.scoreHistory, maxVal: 100, lineColor: kGreen,
                  ),
                ),
        ),
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

  Widget _buildIssueCards() {
    final pitch = widget.data.scores['pitch'] ?? 1.0;
    final eye   = widget.data.scores['eye']   ?? 1.0;
    final avg   = (pitch + eye) / 2;

    final issues = [
      _IssueData('거북목',
        pitch < 0.6 ? '경고' : pitch < 0.75 ? '주의' : '정상',
        Icons.accessibility_new_rounded,
        pitch < 0.6 ? Colors.red : pitch < 0.75 ? Colors.orange : kGreen),
      _IssueData('어깨 기울기',
        eye < 0.6 ? '경고' : eye < 0.75 ? '주의' : '정상',
        Icons.straighten_rounded,
        eye < 0.6 ? Colors.red : eye < 0.75 ? Colors.orange : kGreen),
      _IssueData('허리 자세',
        avg < 0.5 ? '경고' : avg < 0.7 ? '주의' : '정상',
        Icons.airline_seat_recline_normal_rounded,
        avg < 0.5 ? Colors.red : avg < 0.7 ? Colors.orange : kGreen),
    ];

    return Column(children: issues.map(_issueCard).toList());
  }

  Widget _issueCard(_IssueData issue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: issue.color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(issue.icon, color: issue.color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(issue.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: issue.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(issue.status,
              style: TextStyle(
                  color: issue.color, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildGuideCards() {
    const guides = [
      _GuideData('거북목 예방\n스트레칭', '목을 앞으로\n내밀지 마세요', Icons.fitness_center),
      _GuideData('올바른\n앉기 자세', '척추를 곧게\n세우세요', Icons.chair_rounded),
      _GuideData('눈 피로\n완화법', '20-20-20\n규칙을 따르세요', Icons.visibility_rounded),
      _GuideData('어깨 스트레칭', '매 시간 간단한\n스트레칭', Icons.self_improvement),
    ];

    return SizedBox(
      height: 158,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: guides.length,
        separatorBuilder: (_, idx) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          final g = guides[i];
          return Container(
            width: 150,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 6,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: kGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(g.icon, color: kGreen, size: 20),
                ),
                const SizedBox(height: 8),
                Text(g.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Text(g.subtitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IssueData {
  final String   name, status;
  final IconData icon;
  final Color    color;
  const _IssueData(this.name, this.status, this.icon, this.color);
}

class _GuideData {
  final String   title, subtitle;
  final IconData icon;
  const _GuideData(this.title, this.subtitle, this.icon);
}
