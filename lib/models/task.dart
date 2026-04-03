class Task {
  final int? id;
  final String name;
  final DateTime deadline;
  final bool isDone;

  Task({
    this.id,
    required this.name,
    required this.deadline,
    this.isDone = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'deadline': deadline.toIso8601String(),
      'isDone': isDone ? 1 : 0,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      name: map['name'],
      deadline: DateTime.parse(map['deadline']),
      isDone: map['isDone'] == 1,
    );
  }

  Task copyWith({bool? isDone}) {
    return Task(
      id: id,
      name: name,
      deadline: deadline,
      isDone: isDone ?? this.isDone,
    );
  }
}