import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:service_keeper/features/shell/screens/main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  // Logo entrance: scale + fade in
  late final AnimationController _logoCtrl;
  // White → colored logo crossfade
  late final AnimationController _colorCtrl;
  // Title: letter-spacing collapse + fade + slide
  late final AnimationController _titleCtrl;
  // Tagline fade
  late final AnimationController _taglineCtrl;
  // Exit: whole screen fades out
  late final AnimationController _exitCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _colorFade;   // 0=white, 1=colored
  late final Animation<double> _titleFade;
  late final Animation<double> _titleSlide;  // px offset Y
  late final Animation<double> _letterSpacing; // 8→0.5
  late final Animation<double> _taglineFade;
  late final Animation<double> _exitFade;   // 1→0

  @override
  void initState() {
    super.initState();

    _logoCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _colorCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _titleCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _taglineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _exitCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

    _logoScale = Tween<double>(begin: 0.68, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );

    _colorFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _colorCtrl, curve: Curves.easeInOut),
    );

    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _titleCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _titleSlide = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(parent: _titleCtrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic)),
    );
    _letterSpacing = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _titleCtrl, curve: Curves.easeOut),
    );

    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOut),
    );

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    // Logo scale in
    _logoCtrl.forward();

    // White → colored crossfade starts as logo settles
    await Future.delayed(const Duration(milliseconds: 480));
    if (!mounted) return;
    _colorCtrl.forward();

    // Title animates in while color is transitioning
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    _titleCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    _taglineCtrl.forward();

    // Hold, then exit
    await Future.delayed(const Duration(milliseconds: 1050));
    if (!mounted) return;

    await _exitCtrl.forward();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainShell(),
        transitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _colorCtrl.dispose();
    _titleCtrl.dispose();
    _taglineCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final Color bgTop    = dark ? const Color(0xFF155E4E) : const Color(0xFF1E9880);
    final Color bgBottom = dark ? const Color(0xFF0A3D31) : const Color(0xFF0D6658);

    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _exitFade,
        builder: (_, child) => Opacity(opacity: _exitFade.value, child: child),
        child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: Stack(
          children: [
            // Radial glow, grows with logo
            AnimatedBuilder(
              animation: _logoFade,
              builder: (_, __) => Opacity(
                opacity: _logoFade.value * 0.40,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.10),
                      radius: 0.70,
                      colors: [
                        Colors.white.withValues(alpha: 0.40),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo: white → colored crossfade ──────────────────────
                  AnimatedBuilder(
                    animation: Listenable.merge([_logoCtrl, _colorCtrl]),
                    builder: (_, __) {
                      return Transform.scale(
                        scale: _logoScale.value,
                        child: Opacity(
                          opacity: _logoFade.value,
                          child: SizedBox(
                            width: 148,
                            height: 148,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Colored logo (fades IN)
                                Opacity(
                                  opacity: _colorFade.value,
                                  child: Image.asset(
                                    'lib/assets/logo-no-bg.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                // White logo (fades OUT)
                                Opacity(
                                  opacity: 1.0 - _colorFade.value,
                                  child: Image.asset(
                                    'lib/assets/logo-white-no-bg.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 38),

                  // ── App name: letter-spacing collapse + slide + fade ──────
                  AnimatedBuilder(
                    animation: _titleCtrl,
                    builder: (_, __) {
                      final spacing = lerpDouble(7.0, 0.8, _letterSpacing.value)!;
                      return Transform.translate(
                        offset: Offset(0, _titleSlide.value),
                        child: Opacity(
                          opacity: _titleFade.value,
                          child: Text(
                            'Service Keeper',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: spacing,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  // ── Tagline ───────────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _taglineCtrl,
                    builder: (_, child) => Opacity(opacity: _taglineFade.value, child: child),
                    child: Text(
                      'Keep your services alive',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
