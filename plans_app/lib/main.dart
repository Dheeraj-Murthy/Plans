import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:plans_app/src/rust/api.dart' as rust_api;
import 'package:plans_app/src/rust/frb_generated.dart';
import 'theme/app_theme.dart';
import 'routing/app_router.dart';
import 'shared/database/database_service.dart';
import 'shared/notifications/notification_service.dart';
import 'package:home_widget/home_widget.dart';

final widgetIntentProvider = Provider<Map<String, String>?>((ref) => null);
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isMacOS) {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        '@rpath/plans_core.framework/plans_core',
      ),
    );
  } else if (!kIsWeb && Platform.isLinux) {
    await _initRustLib(
      devPath: 'rust/target/release/libplans_core.so',
      soname: 'libplans_core.so',
    );
  } else if (!kIsWeb && Platform.isWindows) {
    await _initRustLib(
      devPath: 'rust/target/release/plans_core.dll',
      soname: 'plans_core.dll',
    );
  } else if (!kIsWeb) {
    await RustLib.init();
  }

  Map<String, String>? initialIntent;
  if (!kIsWeb && Platform.isAndroid) {
    try {
      const deeplinkChannel = MethodChannel('plans/widget/deeplink');
      final raw = await deeplinkChannel.invokeMethod<Map>('getInitialIntent');
      if (raw != null) {
        initialIntent = raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
    } catch (_) {}
  }

  final dir = await getApplicationDocumentsDirectory();
  await rust_api.initDatabase(path: '${dir.path}/plans.db');
  await NotificationService.init();
  NotificationService.navigatorKey = navigatorKey;

  if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
    try {
      await HomeWidget.setAppGroupId('group.com.plansapp');
    } catch (_) {}
  }

  final db = DatabaseService();

  runApp(
    ProviderScope(
      overrides: [
        databaseServiceProvider.overrideWithValue(db),
        widgetIntentProvider.overrideWithValue(initialIntent),
      ],
      child: PlansApp(),
    ),
  );

}

/// Try dev path (flutter run) first, fall back to soname (release bundle).
Future<void> _initRustLib({required String devPath, required String soname}) async {
  final tryPaths = [devPath, soname];
  for (final p in tryPaths) {
    try {
      await RustLib.init(externalLibrary: ExternalLibrary.open(p));
      return;
    } catch (_) {}
  }
  await RustLib.init();
}

class PlansApp extends ConsumerWidget {
  const PlansApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = createRouter(navigatorKey);
    return MaterialApp.router(
      title: 'Plans',
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
