import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/posture_state.dart';

class CameraTab extends StatelessWidget {
  final PostureState        data;
  final bool                connected;
  final AnimationController warnAnim;

  const CameraTab({
    super.key,
    required this.data,
    required this.connected,
    required this.warnAnim,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('실시간 모니터링',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            _scoreChip(data.score),
          ]),
          const SizedBox(height: 14),
          Expanded(child: _buildCameraFeed()),
          const SizedBox(height: 14),
          _buildWarning(),
          const SizedBox(height: 8),
          _buildSubRow(),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _scoreChip(int score) {
    final col = score > 65 ? kGreen : score > 40 ? Colors.orange : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: col, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$score 점',
            style: TextStyle(
                color: col, fontWeight: FontWeight.bold, fontSize: 14)),
      ]),
    );
  }

  Widget _buildCameraFeed() {
    Widget inner;
    if (!connected) {
      inner = _placeholder(Icons.wifi_off_rounded, '서버 연결 중...');
    } else if (data.frame.isEmpty) {
      inner = switch (data.status) {
        'error_no_camera' => _placeholder(Icons.videocam_off_rounded, '카메라 없음'),
        'no_person'       => _placeholder(Icons.person_off_rounded,   '사람 미감지'),
        'calibrating'     => _calibratingOverlay(),
        _                 => _placeholder(Icons.hourglass_top_rounded, '시작 중...'),
      };
    } else {
      final Uint8List bytes = base64Decode(data.frame);
      inner = Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
          if (data.status == 'calibrating') _calibratingOverlay(),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(color: const Color(0xFF1A1A2E), child: inner),
    );
  }

  Widget _placeholder(IconData icon, String label) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 48, color: Colors.grey[400]),
      const SizedBox(height: 10),
      Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
    ]);
  }

  Widget _calibratingOverlay() {
    return Container(
      color: Colors.black54,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.straighten_rounded, color: kGreen, size: 40),
        const SizedBox(height: 10),
        const Text('바른 자세로 앉아주세요',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 8),
        Text('${data.countdown}',
            style: const TextStyle(
                fontSize: 64, fontWeight: FontWeight.bold, color: kGreen)),
        const Text('초', style: TextStyle(color: Colors.white70, fontSize: 14)),
      ]),
    );
  }

  Widget _buildWarning() {
    if (!data.isFhp) return const SizedBox.shrink();
    return FadeTransition(
      opacity: warnAnim,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
            SizedBox(width: 8),
            Text('거북목 자세 감지! 스트레칭 하세요',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubRow() {
    const labels = {
      'pitch': '피치', 'eye': '눈-어깨', 'vis': '귀 가시성', 'z': 'Z축',
    };
    return Row(
      children: labels.entries.map((e) {
        final v   = data.scores[e.key] ?? 1.0;
        final col = v > 0.65 ? kGreen : v > 0.40 ? Colors.orange : Colors.red;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04), blurRadius: 4,
                ),
              ],
            ),
            child: Column(children: [
              Text('${(v * 100).clamp(0, 100).toInt()}',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: col)),
              const SizedBox(height: 2),
              Text(e.value,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ]),
          ),
        );
      }).toList(),
    );
  }
}
