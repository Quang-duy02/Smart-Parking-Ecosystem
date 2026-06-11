import 'package:flutter/material.dart';

class ShakerWidget extends StatefulWidget {
  final Widget child;
  final bool shake;

  const ShakerWidget({super.key, required this.child, required this.shake});

  @override
  State<ShakerWidget> createState() => _ShakerWidgetState();
}

class _ShakerWidgetState extends State<ShakerWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    if (widget.shake) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ShakerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shake && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.shake && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double offset = widget.shake 
            ? (6.0 * (0.5 - _controller.value).abs() * 2 - 3.0) 
            : 0.0;
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
