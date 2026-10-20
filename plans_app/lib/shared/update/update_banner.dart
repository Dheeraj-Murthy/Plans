import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/app_theme.dart';

class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateProvider);
    if (info == null) return const SizedBox.shrink();

    return Material(
      color: AppColors.accent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.system_update_rounded, size: 18, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Update available: v${info.version}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication),
                child: const Text('UPDATE', style: TextStyle(color: Colors.white)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                onPressed: () => ref.read(updateProvider.notifier).dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
