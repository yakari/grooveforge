import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_engine.dart';
import 'synthesizer_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final engine = context.read<AudioEngine>();
    // Wait for the very first frame to finish before starting the heavy lifting and status updates
    await Future.delayed(const Duration(milliseconds: 100));
    await engine.init();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                const SynthesizerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A24),
      body: Stack(
        children: [
          // Background Image (Fullscreen)
          Positioned.fill(
            child: Image.asset(
              'splashscreen.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback in case the asset isn't bundled or registered correctly yet
                return Container(
                  color: const Color(0xFF1A1A24),
                  child: const Center(
                    child: Icon(Icons.piano, size: 150, color: Colors.white),
                  ),
                );
              },
            ),
          ),
          // Semi-transparent overlay at the bottom for readability
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),
          ),
          // Dynamic Progress Area
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 64.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: Colors.white70,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Consumer<AudioEngine>(
                    builder: (context, engine, child) {
                      return ValueListenableBuilder<String>(
                        valueListenable: engine.initStatus,
                        builder: (context, status, child) {
                          return Text(
                            status,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  blurRadius: 8.0,
                                  color: Colors.black,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
