import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants.dart';
import '../models/posture_state.dart';
import '../models/posture_snapshot.dart';
import 'home_tab.dart';
import 'report_tab.dart';
import 'camera_tab.dart';
import 'reward_tab.dart';
import 'profile_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int               _tabIndex  = 0;
  WebSocketChannel? _channel;
  PostureState      _data      = PostureState.initial;
  bool              _connected = false;
  late AnimationController _warnAnim;

  final List<double>              _scoreHistory = [];
  final Map<String, List<double>> _subHistory   = {
    'pitch': [], 'eye': [], 'vis': [], 'z': [],
  };

  // 2분 스냅샷 (시작 직후 즉시 1회 + 이후 2분마다)
  final List<PostureSnapshot> _snapshots     = [];
  Timer?                      _snapshotTimer;
  bool                        _firstSnapshot = false;

  static const _winTitle = '포스처가드 서버';

  int get _todayScore {
    if (_snapshots.isEmpty) return 0;
    return (_snapshots.map((s) => s.score).reduce((a, b) => a + b) /
            _snapshots.length)
        .round();
  }

  @override
  void initState() {
    super.initState();
    _warnAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _startServer();
    _startSnapshotTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) _killServer();
  }

  void _killServer() {
    Process.runSync('taskkill', ['/F', '/FI', 'WINDOWTITLE eq $_winTitle*']);
  }

  Future<void> _startServer() async {
    // 포트 8000 기존 프로세스 먼저 정리 (이전 세션 잔여 프로세스 충돌 방지)
    await _freePort(8000);

    final serverDir = _resolveServerDir();
    if (serverDir == null) {
      // server/ 폴더를 못 찾으면 이미 켜져 있다고 가정하고 바로 연결 시도
      _connect();
      return;
    }

    try {
      await Process.run(
        'cmd',
        [
          '/c', 'start', _winTitle, 'cmd', '/k',
          'python -m uvicorn server:app --host 0.0.0.0 --port 8000',
        ],
        workingDirectory: serverDir,
      );
    } catch (_) {}

    // MediaPipe 모델 로드까지 충분히 대기 (첫 실행 시 모델 다운로드 포함)
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) _connect();
  }

  // 포트를 점유 중인 프로세스 강제 종료
  Future<void> _freePort(int port) async {
    try {
      final result = await Process.run(
        'cmd',
        ['/c', 'netstat -ano | findstr :$port'],
      );
      for (final line in result.stdout.toString().split('\n')) {
        if (line.contains(':$port ') && line.contains('LISTENING')) {
          final pid = line.trim().split(RegExp(r'\s+')).last.trim();
          if (pid.isNotEmpty) {
            await Process.run('taskkill', ['/F', '/T', '/PID', pid]);
          }
        }
      }
    } catch (_) {}
  }

  String? _resolveServerDir() {
    final candidates = [
      '${File(Platform.resolvedExecutable).parent.path}/server',
      '${Directory.current.path}/server',
    ];
    for (final path in candidates) {
      if (Directory(path).existsSync()) return path;
    }
    return null;
  }

  void _startSnapshotTimer() {
    _snapshotTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _takeSnapshot();
    });
  }

  void _takeSnapshot() {
    if (_connected &&
        (_data.status == 'ok' || _data.status == 'warning') &&
        _data.score > 0) {
      final pitchDeg = (1.0 - (_data.scores['pitch'] ?? 1.0)) * 20.0;
      setState(() => _snapshots.add(PostureSnapshot(
        time:     DateTime.now(),
        score:    _data.score,
        pitchDeg: pitchDeg,
      )));
    }
  }

  void _connect() {
    // 이전 채널 정리 후 재연결
    _channel?.sink.close();
    _channel = null;

    try {
      final ch = WebSocketChannel.connect(Uri.parse(kServerUrl));
      _channel = ch;

      ch.stream.listen(
        (raw) {
          if (!mounted) return;
          // 첫 데이터 수신 시점에 연결 확인 (premature true 방지)
          if (!_connected) setState(() => _connected = true);

          final json = jsonDecode(raw as String) as Map<String, dynamic>;
          final next = PostureState.fromJson(json);
          setState(() {
            _data = next;
            if (next.status == 'ok' || next.status == 'warning') {
              _scoreHistory.add(next.score.toDouble());
              if (_scoreHistory.length > kGraphMax) _scoreHistory.removeAt(0);
              for (final k in _subHistory.keys) {
                _subHistory[k]!.add(next.scores[k] ?? 1.0);
                if (_subHistory[k]!.length > kGraphMax) _subHistory[k]!.removeAt(0);
              }
              if (!_firstSnapshot && next.score > 0) {
                _firstSnapshot = true;
                _takeSnapshot();
              }
            }
          });
        },
        onError: (_) => _onDisconnect(),
        onDone:  ()  => _onDisconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _onDisconnect();
    }
  }

  void _onDisconnect() {
    if (!mounted) return;
    _channel?.sink.close();
    _channel = null;
    setState(() { _connected = false; _data = PostureState.initial; });
    // 2초마다 재시도 (기존 3초 → 빠른 재연결)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _connect();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snapshotTimer?.cancel();
    _channel?.sink.close();
    _warnAnim.dispose();
    _killServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeTab(
        data: _data,
        connected: _connected,
        scoreHistory: _scoreHistory,
        todayScore: _todayScore,
        snapshotCount: _snapshots.length,
      ),
      ReportTab(
        data: _data,
        snapshots: _snapshots,
        todayScore: _todayScore,
      ),
      CameraTab(data: _data, connected: _connected, warnAnim: _warnAnim),
      const RewardTab(),
      const ProfileTab(),
    ];

    return Scaffold(
      backgroundColor: kBg,
      body: screens[_tabIndex],
      floatingActionButton: FloatingActionButton(
        backgroundColor: kGreen,
        elevation: 4,
        shape: const CircleBorder(),
        onPressed: () => setState(() => _tabIndex = 2),
        child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        elevation: 8,
        padding: EdgeInsets.zero,
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.home_rounded,          '홈'),
            _navItem(1, Icons.bar_chart_rounded,     '리포트'),
            const SizedBox(width: 56),
            _navItem(3, Icons.card_giftcard_rounded, '보상'),
            _navItem(4, Icons.person_rounded,        '프로필'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final active = _tabIndex == index;
    return InkWell(
      onTap: () => setState(() => _tabIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? kGreen : Colors.grey[400], size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active ? kGreen : Colors.grey[400],
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
