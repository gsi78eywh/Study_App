import 'package:flutter_test/flutter_test.dart';
import 'package:study_app_mobile/features/practice/models/adaptive_models.dart';

void main() {
  group('Adaptive Models Serialization & Calculation Tests', () {
    test('TodayStudyPlanModel parses from JSON correctly', () {
      final json = {
        "courseId": "course-123",
        "courseName": "Data Structures & Algorithms",
        "courseCode": "CS201",
        "examDate": "2026-09-25T09:00:00Z",
        "daysUntilExam": 9,
        "totalEstimatedMinutes": 25,
        "priorities": [
          {
            "topicName": "Binary Search Trees",
            "masteryPercent": 35.0,
            "status": "High Priority",
            "missedCount": 3,
            "courseId": "course-123"
          },
          {
            "topicName": "Sorting Algorithms",
            "masteryPercent": 62.5,
            "status": "Needs Review",
            "missedCount": 1,
            "courseId": "course-123"
          }
        ],
        "steps": [
          {
            "stepNumber": 1,
            "durationMinutes": 5,
            "stepType": "flashcards",
            "title": "Review 6 Due Flashcards",
            "reason": "Spaced repetition review window is active.",
            "itemCount": 6,
            "targetTopic": "General"
          },
          {
            "stepNumber": 2,
            "durationMinutes": 10,
            "stepType": "retrieval_practice",
            "title": "5 Questions on Binary Search Trees",
            "reason": "Target lowest mastery area (35%).",
            "itemCount": 5,
            "targetTopic": "Binary Search Trees"
          }
        ],
        "aiRecommendation": "Prioritize tree traversals before tackling balancing algorithms.",
        "readiness": {
          "courseId": "course-123",
          "courseName": "Data Structures & Algorithms",
          "overallReadinessPercent": 72.0,
          "questionAccuracyPercent": 68.0,
          "flashcardRetentionPercent": 85.0,
          "spacingDaysActive": 4,
          "unresolvedMistakesCount": 4,
          "examDate": "2026-09-25T09:00:00Z",
          "daysUntilExam": 9,
          "summaryExplanation": "Solid foundational knowledge with 4 targeted misconception areas.",
          "topicMastery": [
            {
              "topicName": "Binary Search Trees",
              "masteryPercentage": 0.35
            }
          ]
        }
      };

      final model = TodayStudyPlanModel.fromJson(json);

      expect(model.courseId, "course-123");
      expect(model.courseCode, "CS201");
      expect(model.daysUntilExam, 9);
      expect(model.priorities.length, 2);
      expect(model.priorities.first.topicName, "Binary Search Trees");
      expect(model.priorities.first.masteryPercent, 35.0);
      expect(model.steps.length, 2);
      expect(model.steps.first.stepType, "flashcards");
      expect(model.readiness.overallReadinessPercent, 72.0);
      expect(model.readiness.unresolvedMistakesCount, 4);
      expect(model.readiness.topicMastery.length, 1);
      expect(model.unresolvedMistakesCount, 4);
      expect(model.topPriorityCourse?.topicName, "Binary Search Trees");
    });

    test('MistakeBankItemModel serialization and properties test', () {
      final json = {
        "questionId": "q-101",
        "studySetId": "set-1",
        "studySetTitle": "Data Structures Set",
        "courseCode": "CS201",
        "courseName": "Data Structures",
        "prompt": "What is the time complexity of searching a balanced BST?",
        "type": "multiple_choice",
        "options": ["O(1)", "O(log n)", "O(n)", "O(n log n)"],
        "correctAnswer": "O(log n)",
        "explanation": "Balanced BST halves search space at each level.",
        "missCount": 3,
        "lastMissedAt": "2026-09-15T15:00:00Z",
        "lastSubmittedAnswer": "O(n)",
        "misconceptionPattern": "Confused linear search with logarithmic tree traversal.",
        "isResolved": false
      };

      final item = MistakeBankItemModel.fromJson(json);

      expect(item.questionId, "q-101");
      expect(item.prompt, "What is the time complexity of searching a balanced BST?");
      expect(item.missCount, 3);
      expect(item.isResolved, false);
      expect(item.misconceptionPattern, contains("Confused linear search"));
    });

    test('SmartSessionPayloadModel serialization test', () {
      final json = {
        "sessionTitle": "⚡ Daily Smart Session",
        "estimatedMinutes": 25,
        "flashcards": [
          {
            "questionId": "fc-1",
            "studySetId": "set-1",
            "prompt": "What is LIFO?",
            "answer": "Last-In, First-Out (Stack)",
            "dimensionTag": "CORE CONCEPT",
            "reasonWhy": "Spaced review due today"
          }
        ],
        "retrievalQuestions": [
          {
            "questionId": "q-1",
            "studySetId": "set-1",
            "prompt": "Which data structure follows FIFO?",
            "type": "multiple_choice",
            "options": [
              {"key": "A", "label": "Stack"},
              {"key": "B", "label": "Queue"}
            ],
            "correctAnswer": "B",
            "explanation": "Queue is FIFO, Stack is LIFO.",
            "stageName": "Retrieval Practice",
            "reasonWhy": "Lowest accuracy topic"
          }
        ],
        "mistakeDrillQuestions": [
          {
            "questionId": "q-old",
            "studySetId": "set-1",
            "prompt": "Queue dequeue is at which end?",
            "type": "multiple_choice",
            "options": [
              {"key": "A", "label": "Front"},
              {"key": "B", "label": "Rear"}
            ],
            "correctAnswer": "A",
            "explanation": "Dequeue from front.",
            "stageName": "Mistake Bank Drill",
            "reasonWhy": "Missed 2 times"
          }
        ]
      };

      final payload = SmartSessionPayloadModel.fromJson(json);

      expect(payload.sessionTitle, "⚡ Daily Smart Session");
      expect(payload.estimatedMinutes, 25);
      expect(payload.flashcards.length, 1);
      expect(payload.retrievalQuestions.length, 1);
      expect(payload.mistakeDrillQuestions.length, 1);
      expect(payload.totalItems, 3);
    });

    test('StudentBrainProfileModel parses 5 daily answers and learning metrics', () {
      final json = {
        "coursesCount": 4,
        "activeSubjectsCount": 3,
        "upcomingDeadlinesCount": 2,
        "weakConceptsCount": 5,
        "masteredConceptsCount": 24,
        "pendingReviewsCount": 14,
        "upcomingExamsCount": 1,
        "priorityCourse": "Data Structures - Trees & Graphs",
        "priorityCourseCode": "CS201",
        "priorityMasteryPercent": 42.0,
        "priorityWhy": "Exam in 5 days; accuracy currently at 42%.",
        "dailyAnswers": {
          "whatDoINeedToDo": "Complete Lab 4 and review 14 flashcards.",
          "whatShouldIStudy": "Data Structures - Trees & Graphs",
          "whatAmIStrugglingWith": "Balancing rotations in AVL trees.",
          "howCanILearnIt": "10-min active recall followed by Socratic drill.",
          "whatShouldIDoNext": "Launch 15-minute Blitz drill."
        }
      };

      final profile = StudentBrainProfileModel.fromJson(json);

      expect(profile.coursesCount, 4);
      expect(profile.weakConceptsCount, 5);
      expect(profile.masteredConceptsCount, 24);
      expect(profile.dailyAnswers.whatShouldIStudy, "Data Structures - Trees & Graphs");
      expect(profile.priorityWhy, contains("Exam in 5 days"));
      expect(profile.priorityCourseCode, "CS201");
    });

    test('AcademicTaskModel serialization and toggle status test', () {
      final json = {
        "id": "task-abc",
        "title": "Algorithms Problem Set 3",
        "dueDate": "2026-09-22T23:59:59Z",
        "type": "assignment",
        "courseCode": "CS301",
        "estimatedDifficulty": "Hard",
        "isCompleted": false,
        "actionSteps": ["Read problem", "Implement DP table", "Test base cases"]
      };

      final task = AcademicTaskModel.fromJson(json);

      expect(task.id, "task-abc");
      expect(task.title, "Algorithms Problem Set 3");
      expect(task.type, "assignment");
      expect(task.courseCode, "CS301");
      expect(task.estimatedDifficulty, "Hard");
      expect(task.isCompleted, false);
      expect(task.actionSteps.length, 3);
      expect(task.daysRemaining, isNotNull);
    });

    test('BreakdownResponseModel parses AI generated milestone steps', () {
      final json = {
        "title": "Term Paper Draft",
        "strategySummary": "Progressive milestone drafting with daily checkpoints.",
        "actionSteps": [
          "Day 1: Formulate Thesis & Outline (45 mins)",
          "Day 2: Write Introduction & Section 1 (60 mins)"
        ]
      };

      final breakdown = BreakdownResponseModel.fromJson(json);

      expect(breakdown.title, "Term Paper Draft");
      expect(breakdown.actionSteps.length, 2);
      expect(breakdown.strategySummary, contains("Progressive milestone"));
    });

    test('RecoveryPlanResponseModel parses recovery intervention payload', () {
      final json = {
        "missedCount": 3,
        "targetedTopics": ["Binary Trees", "AVL Balancing"],
        "recoveryAction": "Targeted retrieval practice",
        "recommendedMinutes": 15,
        "message": "Focus on balancing rotations before moving forward."
      };

      final recovery = RecoveryPlanResponseModel.fromJson(json);

      expect(recovery.missedCount, 3);
      expect(recovery.targetedTopics.length, 2);
      expect(recovery.recommendedMinutes, 15);
      expect(recovery.recoveryAction, "Targeted retrieval practice");
    });
  });
}

