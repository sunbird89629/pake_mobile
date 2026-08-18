import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.tapTarget,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final double tapTarget;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: tapTarget,
    height: tapTarget,
    child: IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      // IconButton 自带 8 的内边距，会把 24 的图标顶出 56 的格子去撑大 Row。
      padding: EdgeInsets.zero,
      color: Colors.white,
      disabledColor: Colors.white24,
    ),
  );
}
