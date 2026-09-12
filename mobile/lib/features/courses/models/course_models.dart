class CourseModel {
  final String id;
  final String code;
  final String name;
  final String colorHex;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<StudySetModel> studySets;

  CourseModel({
    required this.id,
    required this.code,
    required this.name,
    required this.colorHex,
    required this.createdAt,
    this.updatedAt,
    this.studySets = const [],
  });

  factory CourseModel.fromJson(Map<String, dynamic> json) {
    return CourseModel(
      id: json["id"]?.toString() ?? "",
      code: json["code"] ?? "",
      name: json["name"] ?? "",
      colorHex: json["colorHex"] ?? "#6366F1",
      createdAt: DateTime.tryParse(json["createdAt"] ?? "") ?? DateTime.now(),
      updatedAt: json["updatedAt"] != null ? DateTime.tryParse(json["updatedAt"]) : null,
      studySets: (json["studySets"] as List<dynamic>?)
              ?.map((s) => StudySetModel.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "code": code,
        "name": name,
        "colorHex": colorHex,
        "createdAt": createdAt.toIso8601String(),
        "updatedAt": updatedAt?.toIso8601String(),
      };
}

class StudySetModel {
  final String id;
  final String courseId;
  final String title;
  final String? description;
  final int questionCount;
  final DateTime createdAt;
  final List<String> bulletPoints;

  StudySetModel({
    required this.id,
    required this.courseId,
    required this.title,
    this.description,
    this.questionCount = 0,
    required this.createdAt,
    this.bulletPoints = const [],
  });

  factory StudySetModel.fromJson(Map<String, dynamic> json) {
    return StudySetModel(
      id: json["id"]?.toString() ?? "",
      courseId: json["courseId"]?.toString() ?? "",
      title: json["title"] ?? "",
      description: json["description"] ?? json["summary"],
      questionCount: json["questionCount"] ?? (json["questions"] as List?)?.length ?? 0,
      createdAt: DateTime.tryParse(json["createdAt"] ?? "") ?? DateTime.now(),
      bulletPoints: (json["highYieldBulletPoints"] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "courseId": courseId,
        "title": title,
        "description": description,
        "createdAt": createdAt.toIso8601String(),
      };
}
