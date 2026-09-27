import "package:flutter_test/flutter_test.dart";
import "package:study_app_mobile/features/courses/models/grade_models.dart";
import "package:study_app_mobile/features/practice/models/adaptive_models.dart";

void main() {
  group("Grade Tracker & USJ-R GWA Models", () {
    test("CourseGradeModel deserializes USJ-R term grades and computes risk", () {
      final json = {
        "courseId": "course-123",
        "courseCode": "CS-101",
        "courseName": "Data Structures & Algorithms",
        "units": 3.0,
        "targetGrade": 1.5,
        "prelimGrade": 72.0, // < 75.0% = failure risk
        "midtermGrade": 74.0,
        "semiFinalGrade": 76.0,
        "finalGrade": null,
        "prelimWeight": 0.20,
        "midtermWeight": 0.20,
        "semiFinalWeight": 0.20,
        "finalWeight": 0.40,
        "runningPercentage": 74.0,
        "runningGwa": 3.0,
        "riskLevel": "Critical Risk",
        "usjRDescription": "Passing Cutoff (75.0%)",
      };

      final course = CourseGradeModel.fromJson(json);
      expect(course.courseCode, equals("CS-101"));
      expect(course.units, equals(3.0));
      expect(course.riskLevel, equals("Critical Risk"));
      expect(course.prelimGrade, equals(72.0));
      expect(course.runningPercentage, equals(74.0));
    });

    test("GradeSummaryModel computes cumulative GWA and Honors status", () {
      final json = {
        "cumulativeGwa": 1.35,
        "totalUnits": 18.0,
        "honorsStatus": "Dean's List / High Honors",
        "gradingScale": "USJ-R (1.0 - 5.0)",
        "courses": [
          {
            "courseId": "c1",
            "courseCode": "CS-101",
            "courseName": "Intro to CS",
            "units": 3.0,
            "runningPercentage": 93.0,
            "runningGwa": 1.4,
            "riskLevel": "Good Standing",
            "usjRDescription": "Very Good",
            "prelimWeight": 0.2,
            "midtermWeight": 0.2,
            "semiFinalWeight": 0.2,
            "finalWeight": 0.4,
          }
        ],
      };

      final summary = GradeSummaryModel.fromJson(json);
      expect(summary.cumulativeGwa, equals(1.35));
      expect(summary.totalUnits, equals(18.0));
      expect(summary.honorsStatus, equals("Dean's List / High Honors"));
      expect(summary.courses.length, equals(1));
    });

    test("WhatIfResultModel handles attainable and unattainable targets", () {
      final json = {
        "courseId": "c1",
        "courseCode": "MATH-201",
        "targetGwa": 1.5,
        "targetPercentage": 93.0,
        "neededFinalGrade": 88.5,
        "isAchievable": true,
        "assessment": "Target is achievable with an 88.5% on the final exam.",
      };

      final result = WhatIfResultModel.fromJson(json);
      expect(result.neededFinalGrade, equals(88.5));
      expect(result.isAchievable, isTrue);
      expect(result.assessment, contains("88.5%"));
    });
  });

  group("Grade-Risk-Aware Study Priority Engine Models", () {
    test("TodayStudyPlanModel parses gradeRiskLevel and gradeRiskReason", () {
      final json = {
        "courseId": "c1",
        "courseName": "Biochemistry",
        "courseCode": "BIO-201",
        "daysUntilExam": 3,
        "totalEstimatedMinutes": 25,
        "priorities": [],
        "steps": [],
        "aiRecommendation": "Critical grade risk detected in BIO-201 (71% Prelim). Prioritize active recall.",
        "gradeRiskLevel": "Critical Risk",
        "gradeRiskReason": "Grade in critical failure zone (71.0%, cutoff 75.0%)",
        "readiness": {
          "overallReadinessPercent": 62.0,
          "questionAccuracyPercent": 58.0,
          "flashcardRetentionPercent": 65.0,
          "spacingDaysActive": 2,
          "unresolvedMistakesCount": 4,
          "summaryExplanation": "Active error patterns flagged.",
        },
      };

      final plan = TodayStudyPlanModel.fromJson(json);
      expect(plan.gradeRiskLevel, equals("Critical Risk"));
      expect(plan.gradeRiskReason, contains("cutoff 75.0%"));
      expect(plan.courseCode, equals("BIO-201"));
      expect(plan.daysUntilExam, equals(3));
    });
  });
}
