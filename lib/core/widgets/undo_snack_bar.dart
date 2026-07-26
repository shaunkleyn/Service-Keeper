import 'package:flutter/material.dart';

SnackBar buildUndoSnackBar({
  required String message,
  required VoidCallback onUndo,
  Duration duration = const Duration(seconds: 10),
}) =>
    SnackBar(
      content: _ProgressContent(message: message, duration: duration),
      duration: duration,
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
    );

class _ProgressContent extends StatefulWidget {
  final String message;
  final Duration duration;

  const _ProgressContent({required this.message, required this.duration});

  @override
  State<_ProgressContent> createState() => _ProgressContentState();
}

class _ProgressContentState extends State<_ProgressContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration)..forward();
    _progress = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.message),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: _progress,
          builder: (_, __) => LinearProgressIndicator(
            value: _progress.value,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white70),
            minHeight: 2,
          ),
        ),
      ],
    );
  }
}
