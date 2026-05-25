import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project.dart';
import '../../../shared/database/database_service.dart';
import '../../../shared/sync/sync_service.dart';
import '../../../shared/widgets/widget_bridge.dart';

sealed class SidebarSelection {
  const SidebarSelection();
}

class ViewSelection extends SidebarSelection {
  final ViewType view;
  const ViewSelection(this.view);
}

class ProjectSelection extends SidebarSelection {
  final String projectId;
  const ProjectSelection(this.projectId);
}

enum ViewType { inbox, today, completed, timeline }

final projectsProvider =
    NotifierProvider<ProjectsNotifier, List<Project>>(ProjectsNotifier.new);

class SidebarSelectionNotifier extends Notifier<SidebarSelection> {
  @override
  SidebarSelection build() => const ViewSelection(ViewType.inbox);
  void select(SidebarSelection selection) => state = selection;
}

final sidebarSelectionProvider =
    NotifierProvider<SidebarSelectionNotifier, SidebarSelection>(
  SidebarSelectionNotifier.new,
);

class ProjectsNotifier extends Notifier<List<Project>> {
  late DatabaseService _db;

  @override
  List<Project> build() {
    _db = ref.read(databaseServiceProvider);
    _load();
    return [];
  }

  void _load() {
    _db.getProjects().then((projects) {
      state = projects;
      WidgetBridge.notifyUpdate(allProjects: projects);
    }).catchError((e) {
      debugPrint('ProjectsNotifier._load failed: $e');
    });
  }

  Future<void> addProject(String name, {required int colorIndex}) async {
    final project = await _db.insertProject(name: name, colorIndex: colorIndex);
    ref.read(syncServiceProvider.notifier).markDirty();
    state = [...state, project];
    WidgetBridge.notifyUpdate(allProjects: state);
  }

  Future<void> updateProject(
    String id, {
    required String name,
    required int colorIndex,
  }) async {
    final idx = state.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final updated = state[idx].copyWith(name: name, colorIndex: colorIndex);
    await _db.updateProject(updated);
    ref.read(syncServiceProvider.notifier).markDirty();
    final list = [...state];
    list[idx] = updated;
    state = list;
    WidgetBridge.notifyUpdate(allProjects: state);
  }

  Future<void> deleteProject(String id) async {
    await _db.deleteProject(id);
    ref.read(syncServiceProvider.notifier).markDirty();
    state = state.where((p) => p.id != id).toList();
    final selection = ref.read(sidebarSelectionProvider);
    if (selection is ProjectSelection && selection.projectId == id) {
      ref.read(sidebarSelectionProvider.notifier).select(const ViewSelection(ViewType.inbox));
    }
    WidgetBridge.notifyUpdate(allProjects: state);
  }
}
