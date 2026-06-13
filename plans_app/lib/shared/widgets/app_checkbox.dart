import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AppCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final double size;
  final Color? color;

  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 18,
    this.color,
  });

  Color get _activeColor => color ?? AppColors.accent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? _activeColor : Colors.transparent,
              border: Border.all(
                color: _activeColor.withValues(alpha: value ? 1 : 0.4),
                width: 2,
              ),
            ),
            child: value
                ? Icon(Icons.check, size: size * 0.6, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
