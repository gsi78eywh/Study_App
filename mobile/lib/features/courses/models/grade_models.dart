class GradeSummaryModel {
  final double cumulativeGwa;
  final double totalUnits;
  final String honorsStatus;
  final String gradingScale;
  final List<CourseGradeModel> courses;

  GradeSummaryModel({
    required this.cumulativeGwa,
    required this.totalUnits,
    required this.honorsStatus,
    required this.gradingScale,
    required this.courses,
  });

  factory GradeSummaryModel.fromJson(Map<String, dynamic> json) {
    return GradeSummaryModel(
      cumulativeGwa: (json["cumulativeGwa"] as num?)?.toDouble() ?? 0.0,
      totalUnits: (json["totalUnits"] as num?)?.toDouble() ?? 0.0,
      honorsStatus: json["honorsStatus"]?.toString() ?? "Good Standing",
      gradingScale: json["gradingScale"]?.toString() ?? "USJ-R (1.0 - 5.0)",
      courses: (json["courses"] as List<dynamic>?)
              ?.map((c) => CourseGradeModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class CourseGradeModel {
  final String courseId;
  final String courseCode;
  final String courseName;
  final double units;
  final double? targetGrade;
  final double? prelimGrade;
  final double? midtermGrade;
  final double? semiFinalGrade;
  final double? finalGrade;
  final double prelimWeight;
  final double midtermWeight;
  final double semiFinalWeight;
  final double finalWeight;
  final double? runningPercentage;
  final double? runningGwa;
  final String riskLevel;
  final String usjRDescription;

  CourseGradeModel({
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.units,
    this.targetGrade,
    this.prelimGrade,
    this.midtermGrade,
    this.semiFinalGrade,
    this.finalGrade,
    required this.prelimWeight,
    required this.midtermWeight,
    required this.semiFinalWeight,
    required this.finalWeight,
    this.runningPercentage,
    this.runningGwa,
    required this.riskLevel,
    required this.usjRDescription,
  });

  factory CourseGradeModel.fromJson(Map<String, dynamic> json) {
    return CourseGradeModel(
      courseId: json["courseId"]?.toString() ?? "",
      courseCode: json["courseCode"]?.toString() ?? "",
      courseName: json["courseName"]?.toString() ?? "",
      units: (json["units"] as num?)?.toDouble() ?? 3.0,
      targetGrade: (json["targetGrade"] as num?)?.toDouble(),
      prelimGrade: (json["prelimGrade"] as num?)?.toDouble(),
      midtermGrade: (json["midtermGrade"] as num?)?.toDouble(),
      semiFinalGrade: (json["semiFinalGrade"] as num?)?.toDouble(),
      finalGrade: (json["finalGrade"] as num?)?.toDouble(),
      prelimWeight: (json["prelimWeight"] as num?)?.toDouble() ?? 0.20,
      midtermWeight: (json["midtermWeight"] as num?)?.toDouble() ?? 0.20,
      semiFinalWeight: (json["semiFinalWeight"] as num?)?.toDouble() ?? 0.20,
      finalWeight: (json["finalWeight"] as num?)?.toDouble() ?? 0.40,
      runningPercentage: (json["runningPercentage"] as num?)?.toDouble(),
      runningGwa: (json["runningGwa"] as num?)?.toDouble(),
      riskLevel: json["riskLevel"]?.toString() ?? "Normal",
      usjRDescription: json["usjRDescription"]?.toString() ?? "Passing",
    );
  }
}

class WhatIfResultModel {
  final String courseId;
  final String courseCode;
  final double targetGwa;
  final double targetPercentage;
  final double? neededFinalGrade;
  final bool isAchievable;
  final String assessment;

  WhatIfResultModel({
    required this.courseId,
    required this.courseCode,
    required this.targetGwa,
    required this.targetPercentage,
    this.neededFinalGrade,
    required this.isAchievable,
    required this.assessment,
  });

  factory WhatIfResultModel.fromJson(Map<String, dynamic> json) {
    return WhatIfResultModel(
      courseId: json["courseId"]?.toString() ?? "",
      courseCode: json["courseCode"]?.toString() ?? "",
      targetGwa: (json["targetGwa"] as num?)?.toDouble() ?? 3.0,
      targetPercentage: (json["targetPercentage"] as num?)?.toDouble() ?? 75.0,
      neededFinalGrade: (json["neededFinalGrade"] as num?)?.toDouble(),
      isAchievable: json["isAchievable"] as bool? ?? true,
      assessment: json["assessment"]?.toString() ?? "",
    );
  }
}
