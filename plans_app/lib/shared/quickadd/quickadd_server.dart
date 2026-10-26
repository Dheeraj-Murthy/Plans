import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

import '../../features/projects/providers/project_provider.dart';
import '../../features/tasks/models/task.dart';
import '../../features/tasks/providers/task_provider.dart';
import '../helpers/task_parser.dart';

/// Local-only convenience server for third-party quick-add integrations
/// (e.g. a Raycast script command, see raycast/README.md). Binds to
/// loopback only — this must never become a network-facing API.
class QuickAddServer {
  static const int port = 51793;

  HttpServer? _server;
  String? _token;

  /// [bindPort] and [tokenFile] exist only so tests can avoid the fixed
  /// production port/token path — omit both in app code.
  Future<void> start(
    ProviderContainer container, {
    int? bindPort,
    File? tokenFile,
  }) async {
    try {
      final token = await _loadOrCreateToken(tokenFile);
      _token = token;
      final router = shelf_router.Router()
        ..get('/health', _healthHandler)
        ..post(
          '/quickadd',
          (Request request) => _quickAddHandler(request, container),
        );

      final handler = const Pipeline()
          .addMiddleware(_authMiddleware(token))
          .addHandler(router.call);

      // Loopback only, always — never anyIPv4/anyIPv6. This is a
      // local-machine convenience feature, not a remote API.
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        bindPort ?? port,
      );
    } catch (e, st) {
      debugPrint('QuickAddServer.start failed: $e\n$st');
    }
  }

  /// Exposed for tests; app code never needs the token directly.
  String? get token => _token;

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Response _healthHandler(Request request) {
    return _json(200, {'status': 'ok'});
  }

  Future<Response> _quickAddHandler(
    Request request,
    ProviderContainer container,
  ) async {
    try {
      final body = await request.readAsString();
      final decoded = body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      final text = (decoded['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        return _json(400, {'error': 'text is required'});
      }

      final projects = container.read(projectsProvider);
      final parsed = TaskParser.parse(text, projects);
      final effectiveTitle = parsed.title.isNotEmpty ? parsed.title : text;
      final effectiveProjectId = parsed.projectId ?? 'default';

      final task = await container.read(tasksProvider.notifier).addTask(
        title: effectiveTitle,
        dueDate: parsed.dueDate,
        priority: parsed.priority ?? TaskPriority.none,
        projectId: effectiveProjectId,
        reminderMinutes: parsed.hasDueDate ? parsed.defaultReminderMinutes : null,
        recurrence: parsed.recurrence,
      );

      return _json(201, {
        'id': task.id,
        'title': task.title,
        'dueDate': task.dueDate?.toIso8601String(),
        'priority': task.priority.name,
        'projectId': task.projectId,
      });
    } catch (e, st) {
      debugPrint('QuickAddServer._quickAddHandler failed: $e\n$st');
      return _json(500, {'error': 'internal error'});
    }
  }

  Response _json(int status, Map<String, dynamic> body) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
  }

  Middleware _authMiddleware(String token) {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.url.path == 'health') {
          return innerHandler(request);
        }
        final header = request.headers['authorization'];
        if (header != 'Bearer $token') {
          return _json(401, {'error': 'unauthorized'});
        }
        return innerHandler(request);
      };
    };
  }

  Future<String> _loadOrCreateToken(File? override) async {
    final home = Platform.environment['HOME'];
    final file = override ?? File('$home/.plans_app/quickadd_token');
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) return existing;
    }
    await file.parent.create(recursive: true);
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await file.writeAsString(token);
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {}
    return token;
  }
}
