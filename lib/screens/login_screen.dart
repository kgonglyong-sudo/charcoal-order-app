// lib/screens/login_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _clientCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isCodeLoading = false;

  late final AnimationController _anim;
  late final _CharcoalParticles _particles;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _particles = _CharcoalParticles(
      spawnAreaPadding: 24,
      particleCount: 140,
      baseSpeed: 18,
      speedJitter: 14,
      baseSize: 2.6,
      sizeJitter: 2.2,
      swirlStrength: 0.35,
      verticalDrift: -1.0,
      alphaMinMax: (0.10, 0.40),
      hue: Colors.redAccent,
      glowColor: Colors.amberAccent,
    );

    _anim.addListener(() {
      _particles.tick(_anim.lastElapsedDuration ?? Duration.zero);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _clientCodeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithCode() async {
    final code = _clientCodeController.text.trim();
    final password = _passwordController.text.trim();

    if (code.isEmpty || password.isEmpty) return _toast('거래처 코드와 비밀번호를 입력해주세요');
    
    setState(() => _isCodeLoading = true);
    
    try {
      final ok = await context.read<AuthService>().login(code, password);
      if (!mounted) return;
      if (!ok) {
        _toast('로그인 정보가 올바르지 않습니다');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('로그인 오류: $e');
    } finally {
      if (mounted) setState(() => _isCodeLoading = false);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _openEmailLoginDialog() {
    showDialog(
      context: context,
      builder: (_) {
        final emailCtrl = TextEditingController();
        final pwCtrl = TextEditingController();
        bool loading = false;

        Future<void> doLogin(StateSetter setSBState) async {
          print('✅ 1단계: 이메일 로그인 버튼 눌림!');
          final email = emailCtrl.text.trim();
          final pw = pwCtrl.text;
          if (email.isEmpty || pw.isEmpty) {
            _toast('이메일/비밀번호를 입력하세요');
            return;
          }
          setSBState(() => loading = true);
          try {
            await context.read<AuthService>().signInWithEmail(email, pw);
            if (mounted) Navigator.of(context).pop();
          } catch (e) {
            print('❌ login_screen에서 에러 발견: $e');
            _toast('이메일 로그인 실패: $e');
          } finally {
            if (mounted) setSBState(() => loading = false);
          }
        }

        return StatefulBuilder(
          builder: (context, setSBState) => AlertDialog(
            title: const Text('이메일로 로그인'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '이메일'),
                    onSubmitted: (_) => doLogin(setSBState),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '비밀번호'),
                    onSubmitted: (_) => doLogin(setSBState),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: loading ? null : () => doLogin(setSBState),
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('로그인'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final orange = Colors.orange.withOpacity(0.95);
    final deepOrange = Colors.deepOrange.withOpacity(0.95);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/back.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final t = _anim.value;
              final screenH = MediaQuery.of(context).size.height;
              final baseRatio = 0.50;
              final pulse = 0.03 * math.sin(t * math.pi * 2);
              final h = screenH * (baseRatio + pulse);
              final alpha = 0.70 + 0.15 * math.sin(t * math.pi * 2 + 1.2);
              return Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                  child: Container(
                    height: h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.amber.withOpacity(alpha),
                          deepOrange.withOpacity(alpha * 0.85),
                          orange.withOpacity(alpha * 0.55),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.35, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final t = _anim.value;
              return Stack(
                children: [
                  _GlowSpot(
                    left: 60 + 12 * math.sin(t * 6.0),
                    bottom: 110 + 10 * math.sin(t * 5.0),
                    size: 100 + 10 * math.sin(t * 7.0),
                    color: Colors.amber.withOpacity(0.22 + 0.06 * math.sin(t * 4.0)),
                  ),
                  _GlowSpot(
                    right: 60 + 10 * math.cos(t * 6.3),
                    bottom: 90 + 8 * math.cos(t * 5.5),
                    size: 120 + 12 * math.cos(t * 6.8),
                    color: Colors.deepOrangeAccent.withOpacity(0.18 + 0.06 * math.cos(t * 3.8)),
                  ),
                ],
              );
            },
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(
                painter: _CharcoalPainter(_particles),
                size: Size.infinite,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/logo-bg.png',
                      width: 200,
                      height: 120,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'SEOUL ENERGY ORDER',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '로그인 방법을 선택하세요',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _clientCodeController,
                            decoration: InputDecoration(
                              labelText: '거래처 코드',
                              hintText: 'CLIENT001, CLIENT002, CLIENT003',
                              prefixIcon: const Icon(Icons.business),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _loginWithCode(),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: '비밀번호',
                              prefixIcon: const Icon(Icons.lock),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onSubmitted: (_) => _loginWithCode(),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isCodeLoading ? null : _loginWithCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isCodeLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      '코드로 로그인',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _openEmailLoginDialog,
                      icon: const Icon(Icons.lock_open, color: Colors.white),
                      label: const Text(
                        '이메일로 로그인 (관리자 전용)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowSpot extends StatelessWidget {
  final double? left;
  final double? right;
  final double bottom;
  final double size;
  final Color color;

  const _GlowSpot({
    this.left,
    this.right,
    required this.bottom,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color, blurRadius: size * 0.6, spreadRadius: size * 0.2),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharcoalParticles {
  _CharcoalParticles({
    required this.spawnAreaPadding,
    required this.particleCount,
    required this.baseSpeed,
    required this.speedJitter,
    required this.baseSize,
    required this.sizeJitter,
    required this.swirlStrength,
    required this.verticalDrift,
    required this.alphaMinMax,
    required this.hue,
    required this.glowColor,
  });

  final double spawnAreaPadding;
  final int particleCount;
  final double baseSpeed;
  final double speedJitter;
  final double baseSize;
  final double sizeJitter;
  final double swirlStrength;
  final double verticalDrift;
  final (double, double) alphaMinMax;
  final Color hue;
  final Color glowColor;

  final math.Random _rand = math.Random();
  final List<_P> _ps = [];
  Size _lastSize = Size.zero;
  Duration _lastTime = Duration.zero;

  void _ensureInit(Size size) {
    if (_ps.isNotEmpty && _lastSize == size) return;
    _ps.clear();
    _lastSize = size;
    final w = size.width;
    final h = size.height;
    for (int i = 0; i < particleCount; i++) {
      _ps.add(_spawn(w, h, randomY: true));
    }
  }

  _P _spawn(double w, double h, {bool randomY = false}) {
    final x = _rand.nextDouble() * (w - spawnAreaPadding * 2) + spawnAreaPadding;
    final y = randomY
        ? h - _rand.nextDouble() * (h * 0.65)
        : h - (spawnAreaPadding + _rand.nextDouble() * 40);
    final speed = baseSpeed + (_rand.nextDouble() * 2 - 1) * speedJitter;
    final size = (baseSize + _rand.nextDouble() * sizeJitter).clamp(1.0, 8.0);
    final alpha = _lerp(alphaMinMax.$1, alphaMinMax.$2, _rand.nextDouble());
    final life = 3.0 + _rand.nextDouble() * 3.0;
    final dirX = (_rand.nextDouble() * 2 - 1) * 0.6;
    final dirY = verticalDrift;
    return _P(
      x: x,
      y: y,
      vx: dirX * speed,
      vy: dirY * speed,
      size: size,
      alpha: alpha,
      life: life,
      age: _rand.nextDouble() * life,
      swirlSeed: _rand.nextDouble() * 1000,
    );
  }

  void tick(Duration now) {
    if (_lastTime == Duration.zero) {
      _lastTime = now;
      return;
    }
    final dt = (now - _lastTime).inMilliseconds / 1000.0;
    _lastTime = now;
    if (_lastSize == Size.zero) return;
    final w = _lastSize.width;
    final h = _lastSize.height;
    for (int i = 0; i < _ps.length; i++) {
      final p = _ps[i];
      final s = p.swirlSeed;
      final swirlX = math.sin((p.age + s) * 1.6) * swirlStrength;
      final swirlY = math.cos((p.age + s) * 1.2) * swirlStrength * 0.6;
      p.x += (p.vx + swirlX) * dt * 10;
      p.y += (p.vy + swirlY) * dt * 10;
      p.age += dt;
      final outOfBound = p.x < -20 || p.x > w + 20 || p.y < -40 || p.y > h + 20;
      if (p.age > p.life || outOfBound) {
        _ps[i] = _spawn(w, h, randomY: false);
      }
    }
  }

  void paint(Canvas canvas, Size size) {
    _ensureInit(size);
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in _ps) {
      final t = (1.0 - (p.age / p.life)).clamp(0.0, 1.0);
      final a = p.alpha * (0.2 + 0.8 * t);
      paint.color = hue.withOpacity(a);
      canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
      final glowA = (a * 0.25).clamp(0.0, 0.3);
      if (glowA > 0) {
        paint.color = glowColor.withOpacity(glowA);
        canvas.drawCircle(Offset(p.x, p.y), p.size * 1.6, paint);
      }
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _P {
  double x, y, vx, vy, size, alpha, life, age, swirlSeed;
  _P({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.alpha,
    required this.life,
    required this.age,
    required this.swirlSeed,
  });
}

class _CharcoalPainter extends CustomPainter {
  final _CharcoalParticles sys;
  _CharcoalPainter(this.sys);

  @override
  void paint(Canvas canvas, Size size) => sys.paint(canvas, size);

  @override
  bool shouldRepaint(covariant _CharcoalPainter oldDelegate) => true;
}