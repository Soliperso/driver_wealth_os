import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.message = 'Loading...',
  });

  final String message;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..forward();

    _progress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF146B5B),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon - rotates to original position at 100%
            AnimatedBuilder(
              animation: _progress,
              builder: (context, child) {
                return RotationTransition(
                  turns: AlwaysStoppedAnimation(_progress.value),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    // An oval, not a rounded rect: the artwork is a rounded
                    // square on a black field, and the circular crop keeps a
                    // ring of that black around it, which is the look wanted.
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icon/app_icon_source.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.trending_up_rounded,
                            size: 50,
                            color: Colors.white,
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            // Text
            Text(
              widget.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            // Horizontal progress bar with percentage
            SizedBox(
              width: 200,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (context, child) {
                        return LinearProgressIndicator(
                          value: _progress.value,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Percentage text
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (context, child) {
                      int percentage = (_progress.value * 100).toInt();
                      return Text(
                        '$percentage%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
