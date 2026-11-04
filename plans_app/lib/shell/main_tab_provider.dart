import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MainTab { tasks, budget }

class MainTabNotifier extends Notifier<MainTab> {
  @override
  MainTab build() => MainTab.tasks;

  void select(MainTab tab) => state = tab;
}

final mainTabProvider = NotifierProvider<MainTabNotifier, MainTab>(
  MainTabNotifier.new,
);
