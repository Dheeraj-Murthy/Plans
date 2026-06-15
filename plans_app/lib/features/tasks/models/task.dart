enum TaskPriority { none, low, medium, high, critical }

const _absent = Object();

class Task {
  final String id;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final TaskPriority priority;
  final bool isCompleted;
  final bool isDeleted;
  final String projectId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sortOrder;
  final int? reminderMinutes;
  final String? recurrence;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.dueDate,
    this.priority = TaskPriority.none,
    this.isCompleted = false,
    this.isDeleted = false,
    this.projectId = 'default',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.sortOrder = 0,
    this.reminderMinutes,
    this.recurrence,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Task copyWith({
    String? id,
    String? title,
    Object? description = _absent,
    Object? dueDate = _absent,
    Object? reminderMinutes = _absent,
    Object? recurrence = _absent,
    TaskPriority? priority,
    bool? isCompleted,
    bool? isDeleted,
    String? projectId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sortOrder,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description == _absent ? this.description : description as String?,
      dueDate: dueDate == _absent ? this.dueDate : dueDate as DateTime?,
      reminderMinutes: reminderMinutes == _absent ? this.reminderMinutes : reminderMinutes as int?,
      recurrence: recurrence == _absent ? this.recurrence : recurrence as String?,
      priority: priority ?? this.priority,
      isCompleted: isCompleted ?? this.isCompleted,
      isDeleted: isDeleted ?? this.isDeleted,
      projectId: projectId ?? this.projectId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
