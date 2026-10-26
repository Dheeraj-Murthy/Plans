import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plans_app/features/tasks/providers/task_provider.dart';
import 'package:plans_app/shared/database/database_service.dart';
import 'package:plans_app/shared/quickadd/quickadd_server.dart';

import '../fake_database_service.dart';

Future<void> _waitForTasks(ProviderContainer c) async {
  c.read(tasksProvider);
  await Future(() {});
  await Future(() {});
}

void main() {
  late ProviderContainer container;
  late QuickAddServer server;
  late int port;
  late File tokenFile;
  late Directory tempDir;

  group('QuickAddServer', () {
    setUp(() async {
      final db = FakeDatabaseService();
      container = ProviderContainer(
        overrides: [databaseServiceProvider.overrideWithValue(db)],
      );
      await _waitForTasks(container);

      tempDir = await Directory.systemTemp.createTemp('quickadd_test');
      tokenFile = File('${tempDir.path}/quickadd_token');

      port = 51800 + (DateTime.now().microsecondsSinceEpoch % 500);
      server = QuickAddServer();
      await server.start(container, bindPort: port, tokenFile: tokenFile);
    });

    tearDown(() async {
      await server.stop();
      container.dispose();
      await tempDir.delete(recursive: true);
    });

    test('GET /health returns 200 without auth', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:$port/health'),
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), {'status': 'ok'});
    });

    test('POST /quickadd without token returns 401', () async {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/quickadd'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'text': 'Buy milk'}),
      );
      expect(response.statusCode, 401);
    });

    test('POST /quickadd with bad token returns 401', () async {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/quickadd'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer wrong-token',
        },
        body: jsonEncode({'text': 'Buy milk'}),
      );
      expect(response.statusCode, 401);
    });

    test('POST /quickadd with good token adds a task', () async {
      final token = server.token;
      expect(token, isNotNull);

      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/quickadd'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({'text': 'Buy milk tomorrow p1'}),
      );
      expect(response.statusCode, 201);

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      expect(decoded['title'], 'Buy milk');
      expect(decoded['priority'], 'high');

      final tasks = container.read(tasksProvider);
      expect(tasks.length, 1);
      expect(tasks.first.title, 'Buy milk');
    });

    test('POST /quickadd with empty text returns 400', () async {
      final token = server.token;
      final response = await http.post(
        Uri.parse('http://127.0.0.1:$port/quickadd'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({'text': '   '}),
      );
      expect(response.statusCode, 400);

      final tasks = container.read(tasksProvider);
      expect(tasks, isEmpty);
    });
  });
}
