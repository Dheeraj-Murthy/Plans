import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/tasks/providers/task_provider.dart';
import '../../theme/app_typography.dart';
import '../../theme/app_theme.dart';
import 'notification_service.dart';

class AlarmFullScreenScreen extends ConsumerStatefulWidget {
  final int alarmId;
  final String taskId;
  final String taskTitle;

  const AlarmFullScreenScreen({
    super.key,
    required this.alarmId,
    required this.taskId,
    required this.taskTitle,
  });

  @override
  ConsumerState<AlarmFullScreenScreen> createState() => _AlarmFullScreenScreenState();
}

class _AlarmFullScreenScreenState extends ConsumerState<AlarmFullScreenScreen> {
  @override
  void dispose() {
    NotificationService.onFullScreenAlarmDismissed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.taskTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const Spacer(flex: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: [
                    Expanded(
                      child: _AlarmButton(
                        label: 'Snooze 5 min',
                        icon: Icons.nightlight_round,
                        onTap: _snooze,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _AlarmButton(
                        label: 'Complete',
                        icon: Icons.check_circle_outline_rounded,
                        onTap: _complete,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _snooze() async {
    await Alarm.stop(widget.alarmId);
    if (!mounted) return;
    NotificationService.snooze(
      alarmId: widget.alarmId,
      taskId: widget.taskId,
      taskTitle: widget.taskTitle,
      minutes: 5,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _complete() async {
    await Alarm.stop(widget.alarmId);
    if (!mounted) return;
    ref.read(tasksProvider.notifier).toggleTask(widget.taskId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _AlarmButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AlarmButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(label, style: AppTypography.bodyMedium),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
