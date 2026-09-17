using System.Text.RegularExpressions;
using StudyApp.Application.DTOs.Ai;

namespace StudyApp.Infrastructure.AiServices;

public static class AcademicTutorSynthesizer
{
    private const string OfflineNotice = "\n\n> 💡 **Tutor Note:** *Answered using the built-in educational tutor knowledge engine. To connect live to Google Gemini cloud AI, tap the 🔑 key icon in the top bar to set your Gemini API key.*";

    public static string SynthesizeResponse(string message, string? contextTopic, List<ChatMessageDto>? history = null)
    {
        var rawPrompt = (message ?? string.Empty).Trim();
        var lowerPrompt = rawPrompt.ToLowerInvariant();
        var topic = (contextTopic ?? string.Empty).Trim();
        var lowerTopic = topic.ToLowerInvariant();

        // 1. Code Documentation, Docstrings & Technical Specifications
        if (Regex.IsMatch(lowerPrompt, @"\b(code documentation|document(?:ing)? code|docstrings?|xml doc(?:umentation)?|jsdoc|tsdoc|dartdoc|swagger|openapi doc|function documentation|api doc(?:umentation)?)\b"))
        {
            return BuildCodeDocumentationResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 2. Flutter Setup & Getting Started
        if (Regex.IsMatch(lowerPrompt, @"\bflutter\b") && (Regex.IsMatch(lowerPrompt, @"\b(setup|install|start|create|begin|init|get started|configure)\b") || lowerPrompt.Length < 35))
        {
            return BuildFlutterSetupResponse() + OfflineNotice;
        }

        // 2. Flutter General / Widgets / State Management
        if (Regex.IsMatch(lowerPrompt, @"\b(flutter|dart|widget|stateful|stateless|provider|bloc|riverpod)\b"))
        {
            return BuildFlutterDevelopmentResponse(rawPrompt) + OfflineNotice;
        }

        // 3. Quick Prompt: Analogy
        if (lowerPrompt.Contains("analogy") || lowerPrompt.Contains("explain this simply") || lowerPrompt.Contains("simple terms"))
        {
            return BuildAnalogyResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 4. Quick Prompt: Formulas & Variables
        if (lowerPrompt.Contains("formula") || lowerPrompt.Contains("equation") || lowerPrompt.Contains("variable"))
        {
            return BuildFormulaBreakdownResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 5. Quick Prompt: High-Yield Practice Problem
        if (lowerPrompt.Contains("practice problem") || lowerPrompt.Contains("practice question") || lowerPrompt.Contains("quiz me"))
        {
            return BuildPracticeProblemResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 6. Quick Prompt: Exam Pitfalls
        if (lowerPrompt.Contains("pitfall") || lowerPrompt.Contains("common mistake") || lowerPrompt.Contains("exam trap"))
        {
            return BuildExamPitfallsResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 7. Quick Prompt: Core Principles / Summary
        if (lowerPrompt.Contains("summarize") || lowerPrompt.Contains("core theoretical") || lowerPrompt.Contains("overview"))
        {
            return BuildCorePrinciplesResponse(rawPrompt, topic) + OfflineNotice;
        }



        // 8. Programming: C# / .NET / ASP.NET Core
        if (Regex.IsMatch(lowerPrompt, @"\b(c#|csharp|\.net|asp\.net|ef core|entity framework|linq)\b"))
        {
            return BuildCSharpResponse(rawPrompt) + OfflineNotice;
        }

        // 9. Programming: Python & Data Science
        if (Regex.IsMatch(lowerPrompt, @"\b(python|django|fastapi|flask|pandas|numpy|matplotlib)\b"))
        {
            return BuildPythonResponse(rawPrompt) + OfflineNotice;
        }

        // 10. Web Development: JavaScript / TypeScript / React / HTML / CSS
        if (Regex.IsMatch(lowerPrompt, @"\b(javascript|typescript|react|next\.?js|html|css|node|express|vue|angular)\b"))
        {
            return BuildWebDevResponse(rawPrompt) + OfflineNotice;
        }

        // 11. Databases & SQL
        if (Regex.IsMatch(lowerPrompt, @"\b(sql|database|postgres|mysql|sqlite|acid|index|foreign key|normalization|query)\b"))
        {
            return BuildDatabaseResponse(rawPrompt) + OfflineNotice;
        }

        // 12. Data Structures & Algorithms
        if (Regex.IsMatch(lowerPrompt, @"\b(algorithm|data structure|binary search|sorting|linked list|tree|graph|big o|recursion|dynamic programming|stack|queue|hash table)\b"))
        {
            return BuildDsaResponse(rawPrompt) + OfflineNotice;
        }

        // 13. Mathematics (Calculus, Linear Algebra, Probability, Statistics)
        if (Regex.IsMatch(lowerPrompt, @"\b(calculus|derivative|integral|matrix|eigenvalue|vector|probability|statistics|normal distribution|bayes)\b") ||
            Regex.IsMatch(lowerTopic, @"\b(math|calculus|algebra|statistics)\b"))
        {
            return BuildMathResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 14. Science: Physics, Chemistry, Biology
        if (Regex.IsMatch(lowerPrompt, @"\b(physics|gravity|momentum|force|energy|thermodynamics|velocity|acceleration|quantum)\b") ||
            Regex.IsMatch(lowerTopic, @"\bphysics\b"))
        {
            return BuildPhysicsResponse(rawPrompt, topic) + OfflineNotice;
        }
        if (Regex.IsMatch(lowerPrompt, @"\b(chemistry|molecule|atom|reaction|stoichiometry|acid|base|covalent|ionic|moles)\b") ||
            Regex.IsMatch(lowerTopic, @"\bchemistry\b"))
        {
            return BuildChemistryResponse(rawPrompt, topic) + OfflineNotice;
        }
        if (Regex.IsMatch(lowerPrompt, @"\b(biology|cell|dna|rna|gene|protein|photosynthesis|mitosis|meiosis|respiration)\b") ||
            Regex.IsMatch(lowerTopic, @"\bbiology\b"))
        {
            return BuildBiologyResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 15. General Structured Academic Response
        return BuildGeneralAcademicResponse(rawPrompt, topic) + OfflineNotice;
    }

    private static string BuildFlutterSetupResponse()
    {
        return """
        ### 🚀 Flutter Development Setup & Starter Guide

        Setting up Flutter enables you to build natively compiled, cross-platform applications for mobile (Android/iOS), web, and desktop from a single, unified Dart codebase.

        ---

        #### 1. System Prerequisites
        - **Operating System:** Windows 10/11 (64-bit), macOS, or Linux.
        - **Git for Windows:** Required for Flutter version control and package resolution ([git-scm.com](https://git-scm.com)).
        - **IDE / Editor:** Visual Studio Code or Android Studio with the official **Flutter** and **Dart** extensions installed.

        ---

        #### 2. Install the Flutter SDK
        1. Download the stable Flutter SDK archive from [flutter.dev](https://docs.flutter.dev/get-started/install).
        2. Extract the archive into a permanent path without elevated permission requirements (e.g. `C:\src\flutter`). Avoid `C:\Program Files` to prevent permission issues.
        3. Add the bin directory to your Environment Variables:
           - In Windows Search, open **Edit the system environment variables**.
           - Under **User variables**, edit `Path` and append: `C:\src\flutter\bin`.

        ---

        #### 3. Verify Environment with Flutter Doctor
        Open a new terminal (PowerShell or Command Prompt) and run the diagnostic check:
        ```bash
        flutter doctor -v
        ```
        This command checks your toolchain:
        - **Flutter & Dart SDK status**
        - **Android Studio / Android SDK Command-line Tools**
        - **Chrome** (for web development)
        - **Connected physical or emulated devices**

        If Android licenses are missing, accept them with:
        ```bash
        flutter doctor --android-licenses
        ```

        ---

        #### 4. Create and Launch Your First App
        ```bash
        # 1. Initialize a new Flutter application
        flutter create my_study_app

        # 2. Change into the project directory
        cd my_study_app

        # 3. Run the development server (Chrome web target)
        flutter run -d chrome
        ```

        ---

        #### 5. Recommended Starter Template (`lib/main.dart`)
        Here is a clean Material 3 starter architecture:

        ```dart
        import 'package:flutter/material.dart';

        void main() {
          runApp(const MyApp());
        }

        class MyApp extends StatelessWidget {
          const MyApp({super.key});

          @override
          Widget build(BuildContext context) {
            return MaterialApp(
              title: 'Study App',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF6366F1),
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              ),
              home: const HomeScreen(),
            );
          }
        }

        class HomeScreen extends StatefulWidget {
          const HomeScreen({super.key});

          @override
          State<HomeScreen> createState() => _HomeScreenState();
        }

        class _HomeScreenState extends State<HomeScreen> {
          int _counter = 0;

          @override
          Widget build(BuildContext context) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Flutter Development'),
                centerTitle: true,
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.rocket_launch, size: 56, color: Color(0xFF6366F1)),
                    const SizedBox(height: 16),
                    Text(
                      'Flutter Setup Complete!',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('Active Sessions: $_counter'),
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () => setState(() => _counter++),
                child: const Icon(Icons.add),
              ),
            );
          }
        }
        ```

        ---

        #### 6. Essential Pro Tips
        - **Hot Reload (`r`):** Instantly injects code changes into your running app in under a second without losing state.
        - **Package Ecosystem:** Add verified community packages via `flutter pub add <package>` (e.g. `flutter pub add dio`, `flutter pub add google_fonts`).
        - **Asset Management:** Declare fonts and images in `pubspec.yaml` under `flutter: assets:`.
        """;
    }

    private static string BuildFlutterDevelopmentResponse(string prompt)
    {
        var subject = CleanQuery(prompt);
        return """
        ### 📱 Flutter & Dart Architecture Guide

        **Topic:** Understanding [SUBJECT]

        ---

        #### 1. Core Principles
        - **Everything is a Widget:** In Flutter, UI components (layouts, text, animations, buttons) are widgets composed in an immutable widget tree.
        - **Declarative UI:** You declare what the interface looks like for a given state (`UI = f(State)`). When state changes, Flutter re-renders the affected widgets efficiently.
        - **Stateless vs. Stateful:**
          - `StatelessWidget`: Immutable; does not retain internal state that alters across builds (e.g., icons, static labels).
          - `StatefulWidget`: Maintains a mutable `State` object that calls `setState()` to trigger a rebuild when data changes.

        ---

        #### 2. Modern Example Pattern

        ```dart
        import 'package:flutter/material.dart';

        class CourseCardWidget extends StatelessWidget {
          final String title;
          final int questionCount;
          final VoidCallback onTap;

          const CourseCardWidget({
            super.key,
            required this.title,
            required this.questionCount,
            required this.onTap,
          });

          @override
          Widget build(BuildContext context) {
            final theme = Theme.of(context);
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.school, color: Color(0xFF6366F1)),
                title: Text(title, style: theme.textTheme.titleMedium),
                subtitle: Text('$questionCount questions available'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: onTap,
              ),
            );
          }
        }
        ```

        ---

        #### 3. High-Yield Best Practices
        - **Use `const` Constructors:** Marking widgets with `const` caches them in memory, preventing redundant rebuilds.
        - **Separation of Concerns:** Keep business logic outside of your UI widgets using state management (`Provider`, `Riverpod`, or `Bloc`).
        - **Responsive Design:** Utilize `LayoutBuilder`, `MediaQuery`, or `Flexible`/`Expanded` to ensure layouts look great across mobile, tablet, and desktop viewports.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildAnalogyResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 💡 Conceptual Analogy: [SUBJECT]

        To make complex concepts stick permanently, let's look at this through an intuitive, real-world comparison:

        ---

        #### 🎭 The Real-World Metaphor: The Busy Restaurant Kitchen
        Imagine **[SUBJECT]** as the operating system of a busy gourmet restaurant:
        - **The Client (Orders):** Diners placing orders represent requests or inputs into the system.
        - **The Waitstaff (Router / API):** Takes orders to the back-of-house and brings finished dishes to tables, ensuring the dining room and kitchen communicate without interfering with each other.
        - **The Head Chef (The Central Logic):** Coordinates which ingredients are processed, ensuring recipes are followed step-by-step with exact timing and temperature.
        - **The Pantry & Walk-In Fridge (Data Storage):** Pre-measured, organized storage where ingredients are cataloged for fast retrieval.

        ---

        #### 🔍 Mapping Back to the Academic Theory
        1. **Input / Trigger:** Just like a dinner order enters the queue, the concept begins with an initiating event or signal.
        2. **Processing Pipeline:** The transformation of ingredients mirrors how operations or mathematical functions process data sequentially.
        3. **State & Output:** The final plated meal represents the outcome or resolved state.

        ---

        #### 🧠 Memory Anchor
        Whenever an exam question asks about this mechanism, remember: **No single component operates in isolation; each tier exists to decouple responsibilities and maintain consistency.**
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildFormulaBreakdownResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 🧪 High-Yield Formula & Variable Breakdown: [SUBJECT]

        Understanding equations requires knowing what each variable represents physically and how changing one factor impacts the entire system.

        ---

        #### 1. Core Equation Structure
        ```text
        Output = (Primary Driver × Rate Factor) / (Resistance or Loss Variable)
        ```

        #### 2. Variable Definitions & SI Units
        | Symbol | Meaning / Physical Quantity | Standard Units (SI) | Behavior when Doubled |
        | :--- | :--- | :--- | :--- |
        | **Y** | Dependent Variable / Output | Dimensionless or Units of problem | Doubles directly |
        | **X** | Independent Variable / Input | Seconds (s), Kilograms (kg), etc. | Drives output proportionally |
        | **k** | Constant of Proportionality | Context-specific coefficient | Fixed baseline constant |
        | **R** | Resistance / Damping factor | Ohms, Joules, etc. | Inversely halves output |

        ---

        #### 3. Mathematical Relationships to Memorize
        - **Direct Proportionality:** As the numerator increases, the output increases linearly (Y proportional to X).
        - **Inverse Square Law:** If a distance or radius variable r is squared in the denominator (1 / r^2), doubling the distance decreases the result by a factor of 4.
        - **Conservation Principle:** The total sum of states across a closed system remains constant before and after the interaction.

        ---

        #### 🎯 Exam Trap Alert
        > **Check your unit conversions first!** The most common reason students lose marks is mixing milliseconds with seconds, or centimeters with meters. Always convert to base SI units before calculating.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildPracticeProblemResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 📝 High-Yield Practice Problem: [SUBJECT]

        Test your active recall with this typical exam-level challenge:

        ---

        #### ❓ Problem Statement
        An applied system operating on principles of **[SUBJECT]** begins at an initial baseline state of S_0 = 100 units. Over an elapsed interval of n = 4 steps, an active rate coefficient of k = 1.25 is continuously applied while experiencing a constant linear offset of -15 units per step.

        **Question:** What is the net resultant state of the system at the conclusion of step 4, and which fundamental constraint governs this transformation?

        ---

        #### 💡 Step-by-Step Solution Breakdown

        1. **Identify the Given Values:**
           - Initial state: S_0 = 100
           - Step interval: n = 4
           - Proportional factor: k = 1.25
           - Constant drag / offset: -15 / step

        2. **Apply the Transformation Rule:**
           - Step 1: (100 * 1.25) - 15 = 125 - 15 = 110
           - Step 2: (110 * 1.25) - 15 = 137.5 - 15 = 122.5
           - Step 3: (122.5 * 1.25) - 15 = 153.125 - 15 = 138.125
           - Step 4: (138.125 * 1.25) - 15 = 172.656 - 15 = **157.66 units**

        3. **Conceptual Takeaway:**
           The compound growth rate outpaces linear damping as the cumulative base expands exponentially over successive intervals.

        ---

        #### 🎯 Exam Strategy Tip
        Break multi-step calculations into discrete tables or stages. On timed exams, always estimate boundary limits to quickly eliminate distractor options.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildExamPitfallsResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 🎯 Top Exam Pitfalls & Traps: [SUBJECT]

        Examiners frequently design questions specifically to target common misconceptions. Review these high-yield distractor traps before your test:

        ---

        #### 1. Confusing Correlation with Causation / Conflating Terms
        - **The Trap:** Assuming that two variables changing together implies direct causality, or confusing similarly named concepts (e.g., synchronous vs asynchronous, static vs dynamic typing).
        - **How to Avoid:** Look for control conditions and verify whether an active intervention occurred or if both variables depend on a third hidden factor.

        #### 2. Neglecting Edge Cases and Boundary Limits
        - **The Trap:** Formulating a general solution that works for standard values (n > 1) but breaks at zero, negative numbers, or boundary thresholds (e.g., null pointers, division by zero, empty collections).
        - **How to Avoid:** Always test three edge values in your head: `0`, `1`, and `MAX_LIMIT`.

        #### 3. Failing to Read Negative Stems
        - **The Trap:** Overlooking words like **"NOT"**, **"EXCEPT"**, or **"INCORRECT"** in the question prompt.
        - **How to Avoid:** Re-read the final sentence of the question prompt twice before selecting your final answer.

        #### 4. Off-by-One and Indexing Errors
        - **The Trap:** Forgetting whether an interval is inclusive [a, b] or exclusive [a, b). In zero-indexed languages, array length is always index + 1.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildCorePrinciplesResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 🔍 Core Theoretical Principles: [SUBJECT]

        A concise, structured summary of foundational principles for quick revision:

        ---

        #### 1. Foundational Axioms
        - **Modularity:** Breaking complex problems into independent, reusable sub-components reduces cognitive load and allows isolated verification.
        - **Determinism:** Given identical inputs and starting conditions, a sound theoretical process consistently produces predictable outcomes.
        - **Trade-Off Optimization:** Almost every architectural or academic decision balances competing priorities (e.g. time vs space complexity, latency vs throughput, specificity vs generalization).

        ---

        #### 2. High-Yield Concept Matrix
        | Principle | Primary Function | Real-World Application |
        | :--- | :--- | :--- |
        | **Abstraction** | Hides underlying implementation complexity | Interfaces, APIs, High-level languages |
        | **Encapsulation** | Enforces data integrity and boundaries | Private variables, Class scopes |
        | **Inheritance / Composition** | Facilitates code reuse and polymorphism | Widget trees, Component hierarchies |
        | **Immutability** | Eliminates side effects in state flow | Functional programming, Flutter widgets |

        ---

        #### 3. Revision Checklist
        - [ ] Can you state the primary definition in one sentence?
        - [ ] Can you solve a baseline problem without referencing notes?
        - [ ] Can you explain why the top distractor option is incorrect?
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildCodeDocumentationResponse(string prompt, string? topic)
    {
        var cleanPrompt = string.IsNullOrWhiteSpace(prompt) ? "Code Documentation Standards" : prompt;
        return """"
        ### 📚 Code Documentation & Technical Specification Standards: [PROMPT]

        Professional code documentation clarifies **intent, architectural boundaries, edge cases, and usage contracts**—explaining the *Why* behind the code, rather than merely repeating *What* the syntax executes.

        ---

        #### 1. C# & .NET XML Documentation (`///`)
        In modern .NET 8/9/10, XML documentation enables rich IDE IntelliSense tooltips, compiler validation (`CS1591`), and automated Swagger/OpenAPI schema generation.

        ```csharp
        /// <summary>
        /// Manages active recall question synthesis and flashcard generation from student study notes.
        /// </summary>
        /// <remarks>
        /// This service uses local heuristic analyzers for offline zero-latency fallback and delegates to
        /// Google Gemini 3.6 Flash when cloud credentials are configured.
        /// </remarks>
        public sealed class QuestionGeneratorService : IQuestionGenerator
        {
            /// <summary>
            /// Generates balanced active-recall questions from raw lecture or notebook text.
            /// </summary>
            /// <param name="rawNotes">The raw markdown or plaintext study notes provided by the student.</param>
            /// <param name="targetCount">The desired number of flashcard questions (clamped between 5 and 50).</param>
            /// <param name="cancellationToken">A token to monitor for cancellation requests.</param>
            /// <returns>A structured <see cref="GeneratedStudySetResult"/> containing summary and question entities.</returns>
            /// <exception cref="ArgumentException">Thrown when <paramref name="rawNotes"/> is null or empty.</exception>
            public async Task<GeneratedStudySetResult> GenerateAsync(
                string rawNotes, 
                int targetCount, 
                CancellationToken cancellationToken = default)
            {
                if (string.IsNullOrWhiteSpace(rawNotes))
                {
                    throw new ArgumentException("Study notes content must not be blank.", nameof(rawNotes));
                }

                // Implementation logic...
                return await Task.FromResult(new GeneratedStudySetResult());
            }
        }
        ```

        ---

        #### 2. Python Docstrings (PEP 257 / Google Style)
        Standard in production Python libraries, FastAPI, and data science pipelines:

        ```python
        def calculate_active_recall_retention(repetitions: int, ease_factor: float, interval_days: int) -> float:
            """Calculates estimated memory retention percentage using the SuperMemo SM-2 algorithm.

            Args:
                repetitions (int): The number of consecutive successful quiz recalls.
                ease_factor (float): The current difficulty multiplier (default baseline 2.5).
                interval_days (int): Days elapsed since the previous study session.

            Returns:
                float: Projected percentage probability of retention in range [0.0, 1.0].

            Raises:
                ValueError: If `repetitions` is negative or `ease_factor` is below 1.3.

            Example:
                >>> calculate_active_recall_retention(3, 2.5, 6)
                0.925
            """
            if repetitions < 0 or ease_factor < 1.3:
                raise ValueError("Invalid repetition count or ease factor below minimum bound.")
            return min(1.0, max(0.0, ease_factor / (1.0 + (interval_days * 0.05))))
        ```

        ---

        #### 3. TypeScript / JavaScript (JSDoc / TSDoc)
        Provides rich type hints, deprecation notices, and automated API document generation:

        ```typescript
        /**
         * Represents the offline synchronization payload transmitted between Flutter client and SQLite server.
         *
         * @template TItem - The domain entity type being synchronized.
         */
        export interface SyncPayload<TItem> {
          /** Unix timestamp in milliseconds indicating when local cache was last refreshed. */
          readonly lastSyncedAt: number;
          /** Batch of mutated entities ready for bidirectional merge. */
          readonly items: readonly TItem[];
          /**
           * Resolves conflicting timestamps using server-authoritative Last-Write-Wins strategy.
           *
           * @param serverRecord - The existing row in the primary database.
           * @param incomingRecord - The mutation received from the mobile client.
           * @returns The winning entity to persist.
           */
          resolveConflict(serverRecord: TItem, incomingRecord: TItem): TItem;
        }
        ```

        ---

        #### 4. Dart / Flutter (Dartdoc `///`)
        Used throughout Flutter framework widgets and state stores:

        ```dart
        /// A reactive study timer card supporting Pomodoro and Blitz active-recall sessions.
        ///
        /// Displays remaining seconds with a smooth circular countdown indicator.
        ///
        /// ```dart
        /// StudyTimerCard(
        ///   initialSeconds: 1500,
        ///   onTimerCompleted: () => print('Time for a 5-minute break!'),
        /// )
        /// ```
        class StudyTimerCard extends StatelessWidget {
          /// Total duration of the study sprint in seconds.
          final int initialSeconds;

          /// Callback triggered when the countdown terminates at zero.
          final VoidCallback onTimerCompleted;

          const StudyTimerCard({
            super.key,
            required this.initialSeconds,
            required this.onTimerCompleted,
          });
        }
        ```

        ---

        #### 5. Code Documentation Best Practices Checklist
        | Rule | Objective | Anti-Pattern |
        | :--- | :--- | :--- |
        | **Document Intent** | Clarify *why* a design decision was made. | `// Increments i by 1` |
        | **Specify Contracts** | Clearly document preconditions, postconditions, and exceptions. | Silent unhandled null values |
        | **Keep Synchronized** | Update docs in the exact same commit as code changes. | Stale comments claiming defunct behavior |
        | **Show Working Examples** | Provide copy-pasteable minimal examples for consumers. | Abstract descriptions without context |
        """".Replace("[PROMPT]", cleanPrompt);
    }

    private static string BuildCSharpResponse(string prompt)
    {
        return """
        ### 💻 C# & .NET Architecture: [PROMPT]

        Modern C# (.NET 8/9) combines strong static typing, high performance, and modern language features like pattern matching and records.

        ---

        #### 1. Modern C# Code Pattern
        ```csharp
        using System;
        using System.Collections.Generic;
        using System.Linq;

        // Modern immutable record
        public record StudyModule(Guid Id, string Title, int EstimatedMinutes, bool IsCompleted);

        public class StudyTracker
        {
            private readonly List<StudyModule> _modules = new();

            public void AddModule(string title, int minutes)
            {
                _modules.Add(new StudyModule(Guid.NewGuid(), title, minutes, false));
            }

            // High-performance LINQ query
            public IEnumerable<StudyModule> GetPendingModules() =>
                _modules.Where(m => !m.IsCompleted).OrderBy(m => m.EstimatedMinutes);
        }
        ```

        ---

        #### 2. Key Concepts to Master
        - **`record` vs `class`:** Records provide value-based equality semantics and non-destructive mutation (`with { ... }`), ideal for DTOs and event payloads.
        - **Dependency Injection (DI):** Register services in `Program.cs` as `Transient` (new per request), `Scoped` (one per HTTP request), or `Singleton` (one for entire application lifetime).
        - **Async/Await:** Always propagate `async Task` and pass `CancellationToken` down the call stack to avoid blocking thread pool threads.
        """.Replace("[PROMPT]", CleanQuery(prompt));
    }

    private static string BuildPythonResponse(string prompt)
    {
        return """
        ### 🐍 Python Programming & Data Science: [PROMPT]

        Python emphasizes readable, concise code with a rich ecosystem of standard and third-party libraries.

        ---

        #### 1. Idiomatic Python Pattern
        ```python
        from dataclasses import dataclass
        from typing import List, Optional

        @dataclass
        class Flashcard:
            front: str
            back: str
            retention_score: float = 0.0

            def record_review(self, correct: bool) -> None:
                if correct:
                    self.retention_score = min(1.0, self.retention_score + 0.2)
                else:
                    self.retention_score = max(0.0, self.retention_score - 0.3)

        # List comprehension with filtering
        cards = [Flashcard("What is DRY?", "Don't Repeat Yourself", 0.8)]
        high_yield = [c for c in cards if c.retention_score >= 0.7]
        ```

        ---

        #### 2. Core Best Practices
        - **Virtual Environments:** Always isolate dependencies using `python -m venv .venv` and activate before installing with `pip`.
        - **Type Hinting:** Use `typing` annotations (`def calculate(x: int) -> float:`) to catch bugs early with static type checkers like `mypy`.
        - **Generators & Comprehensions:** Use generator expressions `(x * 2 for x in data)` when working with large datasets to conserve RAM.
        """.Replace("[PROMPT]", CleanQuery(prompt));
    }

    private static string BuildWebDevResponse(string prompt)
    {
        return """
        ### 🌐 Web Development & JavaScript/TypeScript: [PROMPT]

        Modern web applications rely on responsive layout models, asynchronous event loops, and component-based architectures.

        ---

        #### 1. Modern TypeScript / React Pattern
        ```tsx
        import React, { useState } from 'react';

        interface QuestionItem {
          id: string;
          prompt: string;
          options: string[];
          correctIndex: number;
        }

        export const QuizCard: React.FC<{ question: QuestionItem }> = ({ question }) => {
          const [selected, setSelected] = useState<number | null>(null);
          const [isSubmitted, setIsSubmitted] = useState(false);

          return (
            <div className="p-6 bg-slate-900 text-white rounded-2xl shadow-xl max-w-md mx-auto">
              <h3 className="text-lg font-bold mb-4">{question.prompt}</h3>
              <div className="space-y-2">
                {question.options.map((opt, idx) => (
                  <button
                    key={idx}
                    onClick={() => !isSubmitted && setSelected(idx)}
                    className={`w-full p-3 rounded-lg text-left transition ${
                      selected === idx ? 'bg-indigo-600' : 'bg-slate-800 hover:bg-slate-700'
                    }`}
                  >
                    {opt}
                  </button>
                ))}
              </div>
            </div>
          );
        };
        ```

        ---

        #### 2. Core Concepts
        - **Asynchronous Operations:** Understand Promises, `async/await`, and the JavaScript Event Loop (Call Stack, Web APIs, Microtask Queue).
        - **CSS Flexbox & Grid:** Use Flexbox for one-dimensional layouts (row/column alignment) and CSS Grid for two-dimensional grid systems.
        - **State Management:** Keep state as close to where it is used as possible. Lift state up only when multiple siblings need synchronized access.
        """.Replace("[PROMPT]", CleanQuery(prompt));
    }

    private static string BuildDatabaseResponse(string prompt)
    {
        return """
        ### 🗄️ Database Systems & SQL: [PROMPT]

        Databases ensure durability, consistency, and efficient retrieval of structured information.

        ---

        #### 1. High-Yield SQL Query Pattern
        ```sql
        -- Retrieve top active students with completed study sets
        SELECT 
            u.id AS user_id,
            u.full_name,
            COUNT(DISTINCT s.id) AS total_study_sets,
            AVG(q.difficulty) AS avg_difficulty
        FROM users u
        INNER JOIN courses c ON c.user_id = u.id
        INNER JOIN study_sets s ON s.course_id = c.id
        LEFT JOIN questions q ON q.study_set_id = s.id
        WHERE u.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY u.id, u.full_name
        HAVING COUNT(DISTINCT s.id) >= 3
        ORDER BY total_study_sets DESC
        LIMIT 10;
        ```

        ---

        #### 2. Core Principles to Remember
        - **ACID Guarantees:**
          - **Atomicity:** All operations in a transaction succeed or all roll back.
          - **Consistency:** Database transitions only between valid states conforming to constraints.
          - **Isolation:** Concurrent transactions execute without cross-contamination.
          - **Durability:** Committed transactions persist even in power loss.
        - **Indexing:** B-Tree indexes speed up `WHERE`, `JOIN`, and `ORDER BY` operations at the cost of slight write overhead.
        - **Normalization:** 1NF (atomic columns), 2NF (no partial dependencies on composite keys), 3NF (no transitive dependencies).
        """.Replace("[PROMPT]", CleanQuery(prompt));
    }

    private static string BuildDsaResponse(string prompt)
    {
        return """
        ### ⚡ Data Structures & Algorithms: [PROMPT]

        Mastering DSA comes down to pattern recognition, time-space trade-offs, and edge case management.

        ---

        #### 1. Binary Search Implementation (O(log N))
        ```csharp
        public static int BinarySearch(int[] array, int target)
        {
            int left = 0;
            int right = array.Length - 1;

            while (left <= right)
            {
                // Prevent integer overflow: left + (right - left) / 2
                int mid = left + (right - left) / 2;

                if (array[mid] == target)
                    return mid;
                else if (array[mid] < target)
                    left = mid + 1;
                else
                    right = mid - 1;
            }

            return -1; // Element not present
        }
        ```

        ---

        #### 2. Big-O Complexity Comparison
        | Algorithm / Structure | Average Time | Worst Time | Space Complexity |
        | :--- | :--- | :--- | :--- |
        | **Hash Table Lookup** | O(1) | O(N) (collision) | O(N) |
        | **Binary Search** | O(log N) | O(log N) | O(1) iterative |
        | **Quick Sort** | O(N log N) | O(N^2) (bad pivot) | O(log N) stack |
        | **Merge Sort** | O(N log N) | O(N log N) | O(N) auxiliary |
        """.Replace("[PROMPT]", CleanQuery(prompt));
    }

    private static string BuildMathResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 📐 Mathematical Concepts: [SUBJECT]

        ---

        #### 1. Core Mathematical Foundation
        - **Rate of Change (Calculus):** The derivative measures instantaneous rate of change, slope of the tangent line, and marginal sensitivity.
        - **Accumulation (Integration):** The definite integral calculates accumulated area under a curve, volume of solids, or total work done.
        - **Linear Transformations:** A matrix acts as a geometric operator that stretches, rotates, or reflects coordinate space. Eigenvectors represent directions that remain invariant under transformation, scaled by eigenvalues.

        ---

        #### 2. Key Problem-Solving Strategy
        1. **Check Boundary Values:** Evaluate as x approaches 0, infinity, or where denominators equal zero.
        2. **Verify Units & Dimensions:** Every term in an equation must carry identical physical dimensions.
        3. **Symmetry:** Exploiting even/odd function symmetry can reduce integration or algebraic effort significantly.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildPhysicsResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### ⚛️ Physics Principles: [SUBJECT]

        ---

        #### 1. Foundational Laws
        - **Newton's Laws of Motion:**
          1. **Inertia:** An object remains in uniform motion unless acted upon by a net external force.
          2. **Acceleration:** Net force equals mass times acceleration (F = m * a).
          3. **Action-Reaction:** Forces always occur in matched pairs of equal magnitude and opposite direction.
        - **Conservation of Energy:** In an isolated system, total energy is neither created nor destroyed, transforming between kinetic (1/2 * m * v^2), potential (m * g * h), and thermal states.

        ---

        #### 2. Practical Tip for Physics Exams
        Always draw a clean **Free Body Diagram (FBD)** before writing equations. Resolve all forces into orthogonal vector components (x and y) and apply Newton's equations independently.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildChemistryResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 🧪 Chemistry Principles: [SUBJECT]

        ---

        #### 1. Core Chemical Laws
        - **Conservation of Mass:** In a closed chemical reaction, the mass of reactants equals the mass of products. Every stoichiometric equation must balance atoms on both sides.
        - **The Mole Concept:** 1 mole = 6.022 x 10^23 particles (Avogadro's number). Moles connect microscopic atomic mass to macroscopic laboratory grams:
          n = m / M
        - **Bonding Types:**
          - **Ionic:** Electron transfer between metals and nonmetals.
          - **Covalent:** Electron sharing between nonmetals (polar or nonpolar).
          - **Metallic:** Delocalized sea of electrons enabling electrical conductivity.

        ---

        #### 2. Problem-Solving Strategy
        When balancing redox or stoichiometry problems, always convert grams to moles first, use molar ratios from the balanced reaction equation, and then convert back to desired units.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildBiologyResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 🧬 Biological Principles: [SUBJECT]

        ---

        #### 1. Central Dogma of Molecular Biology
        ```text
        DNA (Replication) --> [Transcription] --> mRNA --> [Translation] --> Functional Protein
        ```
        - **Cellular Energetics:**
          - **Photosynthesis:** 6 CO2 + 6 H2O + light --> C6H12O6 + 6 O2 (stored chemical energy).
          - **Cellular Respiration:** Glycolysis --> Krebs Cycle --> Electron Transport Chain produces approx 30-32 ATP per glucose molecule.
        - **Homeostasis:** Organisms maintain dynamic equilibrium through negative feedback loops (e.g. thermoregulation, blood glucose control).

        ---

        #### 2. High-Yield Distinctions
        - **Mitosis:** Produces 2 genetically identical diploid (2n) somatic daughter cells.
        - **Meiosis:** Produces 4 genetically unique haploid (n) gametes via crossing over in Prophase I and independent assortment.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildGeneralAcademicResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        ### 📚 Academic Concept Breakdown: [SUBJECT]

        Here is a structured conceptual guide to help you master this topic:

        ---

        #### 1. Core Definition & Overview
        **[SUBJECT]** refers to the structured study, methodology, or mechanism governing how elements interact within this academic domain. It provides the foundation for analyzing, predicting, and applying theoretical models to real-world scenarios.

        ---

        #### 2. Fundamental Steps / Logical Flow
        1. **Baseline Assessment:** Identify inputs, boundary conditions, and starting constraints.
        2. **Core Operation / Transformation:** Apply governing rules, formulas, or standard principles systematically.
        3. **Verification & Testing:** Check edge cases, ensure units or types match, and confirm internal consistency.

        ---

        #### 3. Practical Example & Application
        Consider an applied scenario where this principle is tested:
        - **Given Condition:** An environment with defined constraints.
        - **Action:** Executing the primary rule or equation.
        - **Result:** The system reaches an equilibrium state that satisfies theoretical criteria.

        ---

        #### 4. Common Exam Pitfalls & Takeaway
        - **Key Distractor:** Confusing this concept with superficially similar terms.
        - **High-Yield Takeaway:** Focus on the primary mechanism and always verify assumptions before jumping to conclusions.
        """.Replace("[SUBJECT]", subject);
    }

    private static string CleanQuery(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "Academic Subject";
        var cleaned = Regex.Replace(raw, @"[^\w\s\-\.]", " ").Trim();
        cleaned = Regex.Replace(cleaned, @"\s+", " ");
        if (cleaned.Length > 50) cleaned = cleaned.Substring(0, 50);
        return char.ToUpper(cleaned[0]) + cleaned.Substring(1);
    }
}
