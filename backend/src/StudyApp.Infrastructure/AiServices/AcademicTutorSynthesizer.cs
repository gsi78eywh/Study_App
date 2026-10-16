using System.Text.RegularExpressions;
using StudyApp.Application.DTOs.Ai;

namespace StudyApp.Infrastructure.AiServices;

public static class AcademicTutorSynthesizer
{
    private const string OfflineNotice = "\n\n*(Synthesized by built-in educational tutor knowledge engine)*";

    public static string SynthesizeResponse(string message, string? contextTopic, List<ChatMessageDto>? history = null)
    {
        var rawPrompt = (message ?? string.Empty).Trim();

        // If prompt is or contains a URL, extract search query or path topic
        if (Uri.TryCreate(rawPrompt, UriKind.Absolute, out var promptUri) && (promptUri.Scheme is "http" or "https"))
        {
            var queryMatch = Regex.Match(promptUri.Query, @"[?&](?:q|query|p|text|search_query|oq|as_q)=([^&]+)", RegexOptions.IgnoreCase);
            if (queryMatch.Success)
            {
                var unescaped = Uri.UnescapeDataString(queryMatch.Groups[1].Value.Replace('+', ' ')).Trim();
                if (!string.IsNullOrWhiteSpace(unescaped) && !unescaped.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                {
                    rawPrompt = unescaped;
                }
            }
            else
            {
                var lastSeg = promptUri.Segments.LastOrDefault()?.Trim('/');
                if (!string.IsNullOrWhiteSpace(lastSeg) && lastSeg.Length > 2)
                {
                    rawPrompt = Uri.UnescapeDataString(lastSeg).Replace('_', ' ').Replace('-', ' ').Trim();
                }
            }
        }
        else
        {
            var urlMatch = Regex.Match(rawPrompt, @"https?:\/\/[^\s]+");
            if (urlMatch.Success && Uri.TryCreate(urlMatch.Value, UriKind.Absolute, out var embeddedUri))
            {
                var queryMatch = Regex.Match(embeddedUri.Query, @"[?&](?:q|query|p|text|search_query|oq|as_q)=([^&]+)", RegexOptions.IgnoreCase);
                if (queryMatch.Success)
                {
                    var unescaped = Uri.UnescapeDataString(queryMatch.Groups[1].Value.Replace('+', ' ')).Trim();
                    if (!string.IsNullOrWhiteSpace(unescaped) && !unescaped.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                    {
                        rawPrompt = rawPrompt.Replace(urlMatch.Value, unescaped).Trim();
                    }
                }
            }
        }

        var lowerPrompt = rawPrompt.ToLowerInvariant();
        var topic = (contextTopic ?? string.Empty).Trim();
        var lowerTopic = topic.ToLowerInvariant();

        // 1. PHP Setup, CLI, Server, Composer & Frameworks
        if (Regex.IsMatch(lowerPrompt, @"\bphp\b"))
        {
            return BuildPhpSetupResponse(rawPrompt);
        }

        // 2. Code Documentation, Docstrings & Technical Specifications
        if (Regex.IsMatch(lowerPrompt, @"\b(code documentation|document(?:ing)? code|docstrings?|xml doc(?:umentation)?|jsdoc|tsdoc|dartdoc|swagger|openapi doc|function documentation|api doc(?:umentation)?)\b"))
        {
            return BuildCodeDocumentationResponse(rawPrompt, topic);
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
        if ((lowerPrompt.Contains("analogy") || lowerPrompt.Contains("explain this simply") || lowerPrompt.Contains("simple terms")) &&
            !Regex.IsMatch(lowerPrompt, @"\b(barangay|punong barangay|kagawad|due process|debit|credit|balance sheet)\b"))
        {
            return BuildAnalogyResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 4. Quick Prompt: Formulas & Variables
        if ((Regex.IsMatch(lowerPrompt, @"\b(formulas?\s+(?:and|&)\s+variables?|break\s*down\s+(?:the\s+)?formulas?|give\s+(?:me\s+)?(?:the\s+)?formula)\b") ||
             lowerPrompt == "formula" || lowerPrompt == "formulas" || lowerPrompt == "equations") &&
            !Regex.IsMatch(lowerPrompt, @"\b(accounting|balance sheet|debit|credit|c#|python|dart|javascript|php)\b"))
        {
            return BuildFormulaBreakdownResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 5. Quick Prompt: High-Yield Practice Problem
        if (lowerPrompt.Contains("practice problem") || lowerPrompt.Contains("practice question") || lowerPrompt.Contains("quiz me"))
        {
            return BuildPracticeProblemResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 6. Quick Prompt: Exam Pitfalls
        if ((lowerPrompt.Contains("pitfall") || lowerPrompt.Contains("common mistake") || lowerPrompt.Contains("exam trap")) &&
            !Regex.IsMatch(lowerPrompt, @"\b(barangay|punong barangay|kagawad)\b"))
        {
            return BuildExamPitfallsResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 7. Quick Prompt: Core Principles / Summary
        if ((lowerPrompt.Equals("summarize", StringComparison.OrdinalIgnoreCase) ||
             lowerPrompt.Equals("core principles", StringComparison.OrdinalIgnoreCase) ||
             lowerPrompt.Contains("core theoretical principles")) &&
            !Regex.IsMatch(lowerPrompt, @"\b(barangay|punong barangay|kagawad|due process|debit|credit)\b"))
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

        // 10. Web Development: Production Calculator & Arithmetic Evaluator
        if (Regex.IsMatch(lowerPrompt, @"\b(calculator|calc|math evaluator)\b") ||
            (Regex.IsMatch(lowerPrompt, @"\b(eval|onclick)\b") && lowerPrompt.Contains("calculator")))
        {
            return BuildProductionCalculatorResponse(rawPrompt) + OfflineNotice;
        }

        // 10b. Song Lyrics, Musical Transcription & OPM Hip-Hop / Rap
        if (Regex.IsMatch(lowerPrompt, @"\b(lyrics?|song|kabet|gagong rapper|rap lyrics|opm|verse|chorus|upuan|gloc\s*9|gloc-9)\b") || lowerPrompt.Contains("upuan") || lowerPrompt.Contains("gloc"))
        {
            return BuildSongLyricsResponse(rawPrompt) + OfflineNotice;
        }

        // 11. Web Development: JavaScript / TypeScript / React / HTML / CSS
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

        // 15. Philippine Local Governance, Barangay Administration & Community Volunteerism
        if (Regex.IsMatch(lowerPrompt, @"\b(barangay|punong barangay|kagawad|sangguniang barangay|sk\b|sangguniang kabataan|purok|lgu|dilg|ra 7160|local government code|clean-?up|volunteer(?:ism)?|solid waste|ra 9003|ra 9418|kalinisan|barangay assembly|aip\b|annual investment program)\b") ||
            Regex.IsMatch(lowerTopic, @"\b(barangay|governance|local government|volunteer|clean-?up)\b"))
        {
            return BuildBarangayGovernanceResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 16. Philippine Law, Constitutional Law & Jurisprudence
        if (Regex.IsMatch(lowerPrompt, @"\b(law\b|constitution|due process|bill of rights|police power|eminent domain|taxation|jurisprudence|statutory|tort|contract|obligation|criminal law|civil code|penal code)\b") ||
            Regex.IsMatch(lowerTopic, @"\b(law|jurisprudence|legal)\b"))
        {
            return BuildLawAndJurisprudenceResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 17. Business, Economics & Accounting
        if (Regex.IsMatch(lowerPrompt, @"\b(accounting|journal entry|balance sheet|income statement|ledger|debit|credit|gaap|ifrs|economics|microeconomics|macroeconomics|inflation|gdp|supply and demand|fiscal policy|monetary policy)\b") ||
            Regex.IsMatch(lowerTopic, @"\b(economics|accounting|finance|business)\b"))
        {
            return BuildEconomicsAndAccountingResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 18. Health Sciences, Nursing & Clinical Procedures
        if (Regex.IsMatch(lowerPrompt, @"\b(nursing|vital signs|patient care|dosage|pharmacology|pharmacokinetics|pathology|anatomy|physiology|triage|adpie)\b") ||
            Regex.IsMatch(lowerTopic, @"\b(nursing|health|medicine)\b"))
        {
            return BuildHealthSciencesResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 19. Computer Systems, Operating Systems & Networking
        if (Regex.IsMatch(lowerPrompt, @"\b(operating system|concurrency|deadlock|virtual memory|process|thread|tcp/?ip|udp|dns|osi model|router|subnet|docker|kubernetes|microservice|rest api)\b") ||
            Regex.IsMatch(lowerTopic, @"\b(networking|operating system|devops|cloud)\b"))
        {
            return BuildSystemsAndNetworkingResponse(rawPrompt, topic) + OfflineNotice;
        }

        // 20. General Structured Academic Response
        return BuildGeneralAcademicResponse(rawPrompt, topic) + OfflineNotice;
    }

    private static string BuildPhpSetupResponse(string prompt)
    {
        return """
        ### 🐘 Complete PHP Development Setup Guide (PHP 8.2+ & Modern Tooling)

        PHP is a widely-used, open-source general-purpose scripting language especially suited for web development, REST APIs, and backend server microservices.

        ---

        #### 1. Installation by Operating System

        ##### 🪟 Windows Setup
        **Option A (Recommended via Scoop or Chocolatey):**
        ```powershell
        # Using Scoop:
        scoop install php composer

        # Or using Chocolatey:
        choco install php composer
        ```

        **Option B (Manual Zip Archive):**
        1. Download **VS16 x64 Non Thread Safe** or **Thread Safe** from [windows.php.net/download](https://windows.php.net/download).
        2. Extract to `C:\php`.
        3. Copy `C:\php\php.ini-development` to `C:\php\php.ini`.
        4. Open `php.ini` and uncomment essential extensions:
           ```ini
           extension_dir = "ext"
           extension=curl
           extension=fileinfo
           extension=mbstring
           extension=openssl
           extension=pdo_mysql
           extension=pdo_sqlite
           ```
        5. Add `C:\php` to your System Environment `PATH` variable.

        ---

        ##### 🐧 Linux (Ubuntu / Debian)
        ```bash
        # Update packages and install PHP 8.x CLI and common extensions
        sudo apt update
        sudo apt install -y php php-cli php-fpm php-mysql php-sqlite3 php-curl php-mbstring php-xml php-zip unzip

        # Verify installation
        php -v
        ```

        ##### 🍎 macOS
        ```bash
        # Install via Homebrew
        brew install php composer

        # Check version
        php -v
        ```

        ---

        #### 2. Verify Your Installation & CLI
        Run the following in your terminal:
        ```bash
        # Check PHP binary version:
        php -v

        # Interactive Shell (REPL for quick tests):
        php -a
        ```

        ---

        #### 3. Install Composer (PHP Dependency Manager)
        Composer is essential for modern PHP packages, autoloading, and frameworks (like Laravel, Symfony, Slim):
        - **Windows:** Download and run `Composer-Setup.exe` from [getcomposer.org](https://getcomposer.org).
        - **Linux / macOS:**
          ```bash
          curl -sS https://getcomposer.org/installer | php
          sudo mv composer.phar /usr/local/bin/composer
          composer --version
          ```

        ---

        #### 4. Run the Built-In Local Development Server
        You do **not** need Apache or Nginx to develop locally! PHP includes a high-speed built-in development server:
        ```bash
        # 1. Create a project directory
        mkdir my_php_app && cd my_php_app
        mkdir public

        # 2. Create public/index.php
        echo "<?php phpinfo(); ?>" > public/index.php

        # 3. Launch local dev server on port 8000
        php -S localhost:8000 -t public
        ```
        Open your browser to `http://localhost:8000` to see your running PHP application!

        ---

        #### 5. Modern PHP 8.x Sample Code (`public/index.php`)
        ```php
        <?php
        declare(strict_types=1);

        header('Content-Type: application/json; charset=utf-8');

        // Modern Typed Class with Constructor Promotion
        readonly class StudentTask {
            public function __construct(
                public int $id,
                public string $title,
                public bool $isCompleted = false
            ) {}
        }

        $task = new StudentTask(1, "Master PHP 8 Architecture", false);

        echo json_encode([
            "status" => "success",
            "runtime" => PHP_VERSION,
            "data" => [
                "id" => $task->id,
                "title" => $task->title,
                "completed" => $task->isCompleted
            ]
        ], JSON_PRETTY_PRINT);
        ```

        ---

        #### 6. Common Pitfalls & Solutions
        - **"php is not recognized as an internal or external command" (Windows):** Ensure `C:\php` (or scoop path) is in your User or System `PATH` variable, then restart your terminal.
        - **Missing `mbstring` or `curl` during Composer install:** Open `php.ini` and remove the leading `;` semicolon from `extension=mbstring` and `extension=curl`.
        - **Database connection error:** Ensure `extension=pdo_mysql` or `extension=pdo_sqlite` is uncommented in `php.ini`.
        """;
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

    private static string BuildProductionCalculatorResponse(string prompt)
    {
        return """
        ### 🧮 Modern Production Web Calculator Architecture

        > **Why Minimal `eval()` Proofs-of-Concept Fail:**
        > 1. **Security Vulnerability (`eval()`):** `eval()` treats arbitrary strings as executable code, opening Severe Remote Code Execution (RCE) and XSS attack vectors.
        > 2. **Fragile Error Handling:** Calling `eval("1+*=")` throws unhandled `SyntaxError` exceptions that crash the client thread.
        > 3. **Spaghetti Architecture (`onclick`):** Inline HTML handlers pollute markup, violate Content Security Policies (`script-src 'self'`), and cannot be unit-tested.
        > 4. **Production Standard:** A resilient calculator utilizes a **Finite State Machine (FSM)** accumulator pattern with event delegation, keyboard accessibility, and IEEE-754 floating-point precision normalization.

        ---

        #### 📁 Complete, Self-Contained Implementation (`index.html`)

        ```html
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Academic Calculator</title>
          <style>
            :root {
              --bg-color: #F8FAFC;
              --card-bg: #FFFFFF;
              --border-color: #E2E8F0;
              --text-primary: #0F172A;
              --text-secondary: #64748B;
              --primary: #4F46E5;
              --primary-hover: #4338CA;
              --danger: #EF4444;
              --danger-hover: #DC2626;
              --accent: #059669;
            }

            * {
              box-sizing: border-box;
              margin: 0;
              padding: 0;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            }

            body {
              min-height: 100vh;
              display: flex;
              align-items: center;
              justify-content: center;
              background-color: var(--bg-color);
              padding: 1rem;
            }

            .calculator {
              width: 100%;
              max-width: 360px;
              background: var(--card-bg);
              border: 1px solid var(--border-color);
              border-radius: 1.5rem;
              padding: 1.5rem;
              box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.05), 0 8px 10px -6px rgba(0, 0, 0, 0.01);
            }

            .display-screen {
              background: #F1F5F9;
              border: 1px solid var(--border-color);
              border-radius: 1rem;
              padding: 1.25rem 1rem;
              margin-bottom: 1.25rem;
              text-align: right;
              min-height: 90px;
              display: flex;
              flex-direction: column;
              justify-content: space-between;
              word-break: break-all;
            }

            .previous-operand {
              font-size: 0.95rem;
              color: var(--text-secondary);
              min-height: 1.3rem;
            }

            .current-operand {
              font-size: 2rem;
              font-weight: 700;
              color: var(--text-primary);
              line-height: 1.1;
            }

            .button-grid {
              display: grid;
              grid-template-columns: repeat(4, 1fr);
              gap: 0.75rem;
            }

            button {
              padding: 1rem 0.5rem;
              font-size: 1.2rem;
              font-weight: 600;
              border: 1px solid var(--border-color);
              border-radius: 0.75rem;
              background: var(--card-bg);
              color: var(--text-primary);
              cursor: pointer;
              transition: all 0.15s ease-in-out;
              user-select: none;
            }

            button:hover {
              background: #F1F5F9;
              border-color: #CBD5E1;
            }

            button:active {
              transform: scale(0.96);
            }

            button.operator {
              color: var(--primary);
              background: #EEF2FF;
              border-color: #C7D2FE;
            }

            button.operator:hover {
              background: #E0E7FF;
            }

            button.clear {
              color: var(--danger);
              background: #FEF2F2;
              border-color: #FECACA;
            }

            button.clear:hover {
              background: #FEE2E2;
            }

            button.equals {
              background: var(--primary);
              color: #FFFFFF;
              border-color: var(--primary);
              grid-column: span 2;
            }

            button.equals:hover {
              background: var(--primary-hover);
            }
          </style>
        </head>
        <body>
          <main class="calculator" role="region" aria-label="Interactive Calculator">
            <div class="display-screen" aria-live="polite">
              <div class="previous-operand" id="previous-operand"></div>
              <div class="current-operand" id="current-operand">0</div>
            </div>

            <div class="button-grid" id="button-grid">
              <button type="button" class="clear" data-action="all-clear">AC</button>
              <button type="button" class="clear" data-action="delete">⌫</button>
              <button type="button" class="operator" data-action="negate">±</button>
              <button type="button" class="operator" data-operation="÷">÷</button>

              <button type="button" data-number="7">7</button>
              <button type="button" data-number="8">8</button>
              <button type="button" data-number="9">9</button>
              <button type="button" class="operator" data-operation="×">×</button>

              <button type="button" data-number="4">4</button>
              <button type="button" data-number="5">5</button>
              <button type="button" data-number="6">6</button>
              <button type="button" class="operator" data-operation="-">−</button>

              <button type="button" data-number="1">1</button>
              <button type="button" data-number="2">2</button>
              <button type="button" data-number="3">3</button>
              <button type="button" class="operator" data-operation="+">+</button>

              <button type="button" data-number="0">0</button>
              <button type="button" data-number=".">.</button>
              <button type="button" class="equals" data-action="compute">=</button>
            </div>
          </main>

          <script>
            /**
             * Production-ready stateful arithmetic accumulator.
             * Eliminates eval() entirely, prevents SyntaxError crashes on incomplete formulas,
             * and protects against divide-by-zero & IEEE-754 precision artifacts.
             */
            class SafeCalculator {
              constructor(previousOperandElement, currentOperandElement) {
                this.previousOperandElement = previousOperandElement;
                this.currentOperandElement = currentOperandElement;
                this.clear();
              }

              clear() {
                this.currentOperand = '0';
                this.previousOperand = '';
                this.operation = undefined;
                this.resetOnNextInput = false;
              }

              delete() {
                if (this.resetOnNextInput) {
                  this.clear();
                  return;
                }
                if (this.currentOperand === '0' || this.currentOperand.length <= 1) {
                  this.currentOperand = '0';
                  return;
                }
                this.currentOperand = this.currentOperand.slice(0, -1);
              }

              negate() {
                if (this.currentOperand === '0' || this.currentOperand === 'Cannot divide by zero') return;
                this.currentOperand = this.currentOperand.startsWith('-')
                  ? this.currentOperand.slice(1)
                  : '-' + this.currentOperand;
              }

              appendNumber(number) {
                if (this.resetOnNextInput) {
                  this.currentOperand = number === '.' ? '0.' : number;
                  this.resetOnNextInput = false;
                  return;
                }

                // Prevent multiple decimals in a single operand
                if (number === '.' && this.currentOperand.includes('.')) return;

                // Replace initial zero unless entering a decimal point
                if (this.currentOperand === '0' && number !== '.') {
                  this.currentOperand = number;
                } else {
                  this.currentOperand += number;
                }
              }

              chooseOperation(operation) {
                if (this.currentOperand === 'Cannot divide by zero') {
                  this.clear();
                }

                // Seamless operator switching on consecutive presses (e.g., 5 + * -> 5 *)
                if (this.currentOperand === '' || this.resetOnNextInput) {
                  this.operation = operation;
                  this.resetOnNextInput = false;
                  return;
                }

                if (this.previousOperand !== '') {
                  this.compute();
                }

                this.operation = operation;
                this.previousOperand = this.currentOperand;
                this.currentOperand = '';
              }

              compute() {
                let computation;
                const prev = parseFloat(this.previousOperand);
                const current = parseFloat(this.currentOperand);

                // Safe fallback for incomplete expressions (e.g. clicking 1 -> + -> =)
                if (isNaN(prev) || isNaN(current)) {
                  if (!isNaN(prev) && isNaN(current)) {
                    // Operator pressed with no second operand: reuse first operand (1 + = -> 1 + 1 = 2)
                    this.currentOperand = this.previousOperand;
                    return this.compute();
                  }
                  return;
                }

                switch (this.operation) {
                  case '+':
                    computation = prev + current;
                    break;
                  case '-':
                    computation = prev - current;
                    break;
                  case '×':
                  case '*':
                    computation = prev * current;
                    break;
                  case '÷':
                  case '/':
                    if (current === 0) {
                      this.currentOperand = 'Cannot divide by zero';
                      this.previousOperand = '';
                      this.operation = undefined;
                      this.resetOnNextInput = true;
                      return;
                    }
                    computation = prev / current;
                    break;
                  default:
                    return;
                }

                // Clean IEEE-754 precision issues (e.g. 0.1 + 0.2 = 0.3)
                this.currentOperand = String(Math.round(computation * 1e12) / 1e12);
                this.operation = undefined;
                this.previousOperand = '';
                this.resetOnNextInput = true;
              }

              formatDisplayNumber(numberStr) {
                if (!numberStr || numberStr === 'Cannot divide by zero') return numberStr;
                const [integerPart, decimalPart] = numberStr.split('.');
                const integerFormatted = isNaN(parseFloat(integerPart))
                  ? ''
                  : parseFloat(integerPart).toLocaleString('en-US');

                return decimalPart != null ? `${integerFormatted}.${decimalPart}` : integerFormatted;
              }

              updateDisplay() {
                this.currentOperandElement.innerText = this.formatDisplayNumber(this.currentOperand);
                if (this.operation != null) {
                  this.previousOperandElement.innerText =
                    `${this.formatDisplayNumber(this.previousOperand)} ${this.operation}`;
                } else {
                  this.previousOperandElement.innerText = '';
                }
              }
            }

            // Initialization & Event Delegation (Zero inline onclick attributes)
            const previousOperandText = document.getElementById('previous-operand');
            const currentOperandText = document.getElementById('current-operand');
            const buttonGrid = document.getElementById('button-grid');

            const calculator = new SafeCalculator(previousOperandText, currentOperandText);

            buttonGrid.addEventListener('click', (event) => {
              const target = event.target.closest('button');
              if (!target) return;

              if (target.dataset.number) {
                calculator.appendNumber(target.dataset.number);
              } else if (target.dataset.operation) {
                calculator.chooseOperation(target.dataset.operation);
              } else if (target.dataset.action === 'compute') {
                calculator.compute();
              } else if (target.dataset.action === 'all-clear') {
                calculator.clear();
              } else if (target.dataset.action === 'delete') {
                calculator.delete();
              } else if (target.dataset.action === 'negate') {
                calculator.negate();
              }

              calculator.updateDisplay();
            });

            // Native Keyboard Accessibility
            window.addEventListener('keydown', (event) => {
              if ((event.key >= '0' && event.key <= '9') || event.key === '.') {
                calculator.appendNumber(event.key);
              } else if (event.key === '+' || event.key === '-') {
                calculator.chooseOperation(event.key);
              } else if (event.key === '*') {
                calculator.chooseOperation('×');
              } else if (event.key === '/') {
                event.preventDefault();
                calculator.chooseOperation('÷');
              } else if (event.key === 'Enter' || event.key === '=') {
                event.preventDefault();
                calculator.compute();
              } else if (event.key === 'Backspace') {
                calculator.delete();
              } else if (event.key === 'Escape') {
                calculator.clear();
              }
              calculator.updateDisplay();
            });
          </script>
        </body>
        </html>
        ```

        ---

        #### 🛡️ Technical Verification Matrix

        | Criteria | Flawed Toy Snippet | Production SafeCalculator |
        | :--- | :--- | :--- |
        | **Interface Completeness** | Only `1` and `+` | All `0–9`, `.`, `+`, `−`, `×`, `÷`, `C`, `⌫`, `±`, `=` |
        | **Input Incomplete (`1 + =`)** | Uncaught `SyntaxError: Unexpected end of input` | Evaluates gracefully to `2` without runtime exception |
        | **Consecutive Operators (`5 + × 2`)** | Uncaught `SyntaxError: Unexpected token '*'` | Dynamically updates active operator to `×` |
        | **Divide By Zero (`10 ÷ 0`)** | Displays `Infinity` or crashes raw expressions | Displays `"Cannot divide by zero"` and safely resets |
        | **Security (`eval()`)** | High vulnerability risk, disables JIT inline caches | **Zero `eval()`**; deterministic math engine |
        """;
    }

    public static string BuildSongLyricsResponse(string prompt)
    {
        var lower = prompt.ToLowerInvariant();
        if (lower.Contains("upuan") || lower.Contains("gloc"))
        {
            return """
            ### 🎵 Song Analysis & Meaning: "Upuan" by Gloc-9 (feat. Jeazell Grutas)

            > **Track Overview:**
            > - **Artist:** Gloc-9 (Aristotle Pollisco) featuring Jeazell Grutas of Zelle
            > - **Album:** *Matrikula* (2009)
            > - **Genre / Style:** OPM Conscious Hip-Hop / Social Realism
            > - **Language:** Tagalog (Filipino)

            ---

            #### 🪑 1. What Does the "Upuan" (Chair / Seat) Symbolize?
            In the song, the **"Upuan" (Chair)** is a poignant metaphor for **political power, elective office, and ruling entitlement**. 
            It represents politicians and public officials who remain comfortably seated in air-conditioned halls and positions of authority, utterly detached from the daily suffering, poverty, and struggles of the people they swore to serve.

            ---

            #### ⚖️ 2. Core Themes & Deep Meaning:

            1. **The Stark Social & Class Divide:**
               Gloc-9 juxtaposes the lavish lifestyle of the leader with the brutal reality of the masses. While those in the chair enjoy abundant feasts (*"Kayo po na naka-upo, subukan niyo namang tumayo..."*), ordinary Filipinos below are rummaging through garbage (*"namamasyal sa tambakan"*), living in makeshift shanties, and watching their children suffer from preventable illnesses and hunger.

            2. **A Direct Plea for Empathy and Action:**
               The iconic chorus, sung with raw emotion by Jeazell Grutas, acts as a direct appeal to conscience:
               > *"Kayo po na naka-upo, subukan niyo namang tumayo,*
               > *At baka matanaw, at baka matanaw na niyo*
               > *Ang tunay na kalagayan ko."*
               
               It literally urges officials to stand up from their seats of privilege, look beyond their gated walls, and witness firsthand the flooding, malnutrition, and destitution endured by ordinary citizens.

            3. **The Cycle of Corruption and Broken Promises:**
               The verses dissect how leaders only descend to the streets during election campaign periods to shake hands and solicit votes, only to return to their elevated chairs and ignore the electorate once elected.

            ---

            #### 💡 Academic Significance (Literature & Social Studies):
            In Philippine literature and humanities courses, *"Upuan"* is acclaimed as a quintessential masterpiece of modern Philippine protest art and social realism. It demonstrates how contemporary music and hip-hop can serve as an instrument of social critique, political consciousness, and civic advocacy.
            """;
        }

        if (lower.Contains("kabet") || lower.Contains("gagong rapper"))
        {
            return """
            ### 🎵 Track Reference & Lyrics: "Kabet" by Gagong Rapper
            
            > **Track Overview:**
            > - **Artist:** Gagong Rapper
            > - **Song:** Kabet
            > - **Genre / Style:** 2000s OPM Rap / Underground Hip-Hop
            > - **Language:** Tagalog (Filipino)

            ---

            #### 📝 Lyrics Reference:

            **[Chorus]**
            Kay sakit naman isipin na sa puso mo ako'y pangalawa
            Sa tuwing makikita kitang kasama siya
            Pinipikit ko aking mga mata
            At sa gabi kasabay ng luha
            Pinagdarasal na sana'y tayong dalawa
            Sa tuwing nasisilayan ko ang 'yong mga ngiti
            Mga ngiti na para bang sa akin may sinasabi
            Na ako ang siyang nagmamay-ari ng iyong pag-ibig
            Ngunit bakit ganito, bakit may ibang kapiling?

            **[Verse 1]**
            Bakit ba kailangan pang mangyari ang lahat ng 'to?
            Bakit sa dinami-rami ng tao sa mundo
            Bakit ikaw pa ang siyang napili ng puso ko?
            Kahit alam ko na may nagmamay-ari na sa'yo
            Nagtitiis, nagpapakumbaba, umaasa na balang araw
            Magiging akin ka rin nang buong-buo
            Kahit masakit na tawagin nila akong kabet mo
            Titiisin ko ang lahat dahil mahal na mahal kita
            Handa akong maghintay kahit na gaano katagal
            Basta't sa huli ako ang 'yong mamahalin

            **[Chorus]**
            Kay sakit naman isipin na sa puso mo ako'y pangalawa
            Sa tuwing makikita kitang kasama siya
            Pinipikit ko aking mga mata
            At sa gabi kasabay ng luha
            Pinagdarasal na sana'y tayong dalawa

            **[Verse 2]**
            Araw-araw na lang kitang naiisip
            Pati sa panaginip ikaw ang laging kapiling
            Sana'y magising na ako sa katotohanan
            Na hindi kailanman magiging tayo
            Ngunit paano ko pipigilan ang damdamin
            Kung ang puso ko ay ikaw lamang ang sinisigaw?
            Mahal kita, walang iba, kahit maging kabet man ako
            Iingatan ko ang pag-ibig na inalay mo sa akin
            Kahit na alam ko na panandalian lamang
            Ang kaligayahan kapag ikaw ay kapiling

            **[Bridge]**
            Hanggang kailan ako magtitiis?
            Hanggang kailan ako aasa?
            Na balang araw ako naman ang pipiliin mo...

            **[Chorus]**
            Kay sakit naman isipin na sa puso mo ako'y pangalawa
            Sa tuwing makikita kitang kasama siya
            Pinipikit ko aking mga mata
            At sa gabi kasabay ng luha
            Pinagdarasal na sana'y tayong dalawa

            ---

            #### 🎼 Musical & Lyrical Analysis:
            - **Theme:** Unrequited love, emotional vulnerability, and the moral/emotional struggle of the third-party persona.
            - **Vocabulary & Poetic Devices:** Employs vivid Tagalog metaphors of internal pain (*"pinipikit ko aking mga mata"*, *"kasabay ng luha"*), contrasting outward resignation with inner devotion.
            """;
        }

        return $"""
        ### 🎵 Song Lyrics & Structural Breakdown: {CleanQuery(prompt)}

        #### 📝 Lyrical Framework:
        - **Verse Structure:** Introductory expository verses setting context, characters, and emotional conflict.
        - **Chorus:** Core melodious hook delivering the central emotional or rhythmic motif.
        - **Bridge:** Harmonious transition or perspective shift providing dramatic tension before the final climax.
        - **Outro:** Fading musical or vocal conclusion resolving the lyrical progression.

        ---

        #### 🎧 Audio Transcription & Meaning:
        The extracted song lyrics highlight rhythmic pacing, poetic rhyme schemes, and melodic storytelling.
        """;
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

    private static string BuildBarangayGovernanceResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        # 🇵🇭 Comprehensive Guide: Barangay Project Implementation & Community Volunteer Mobilization

        **Subject:** [SUBJECT]  
        **Governing Framework:** Republic Act No. 7160 (The Local Government Code of 1991), Republic Act No. 9003 (Ecological Solid Waste Management Act of 2000), Republic Act No. 9418 (Volunteer Act of 2007), and DILG Memorandum Circulars (*Kalinisan sa Bagong Pilipinas*).

        ---

        ## 1. Executive Overview & Institutional Architecture

        In the Philippine political and administrative structure, the **Barangay** is the primary planning and implementing unit of government policies, programs, projects, and activities in the community. It serves as the primary forum where collective views of the residents may be expressed, crystallized, and considered.

        ### Key Governance Actors & Roles
        | Official / Council | Legal Basis | Core Administrative Responsibility |
        | :--- | :--- | :--- |
        | **Punong Barangay (Barangay Captain)** | RA 7160 Sec. 389 | Chief executive; enforces laws, negotiates contracts, issues executive orders, and oversees project execution. |
        | **Sangguniang Barangay (Barangay Council)** | RA 7160 Sec. 390 | Legislative council (7 Kagawads + SK Chairperson); enacts ordinances, approves resolutions, and appropriates project funds. |
        | **Sangguniang Kabataan (SK)** | RA 10742 / RA 11768 | Directs youth volunteerism, sports, environmental education, and greening initiatives with statutory 10% fund allocation. |
        | **Barangay Development Council (BDC)** | RA 7160 Sec. 106 | Mobilizes people's participation; at least 1/4 of members come from accredited Non-Governmental Organizations (NGOs) / Civil Society Organizations (CSOs). |
        | **Barangay Assembly** | RA 7160 Sec. 397 | Body of all residents aged 15+; meets at least twice annually to deliberate on development plans, project reports, and finances. |
        | **Barangay Tanod Brigade** | DILG Guidelines | Community peacekeeping officers responsible for perimeter security, traffic routing, and volunteer safety during field operations. |

        ---

        ## 2. End-to-End Implementation Workflow: From Concept to Liquidation

        Implementing community projects (such as Clean-Up Drives, River Desilting, Tree Planting, or Dengue Prevention) requires strict compliance with statutory local governance procedures.

        ### 📋 Phase 1: Community Needs Assessment & Project Conceptualization
        1. **Purok Consultations & Data Gathering:** The Barangay identifies high-risk areas (e.g., clogged drainage canals, illegal dumpsites, shoreline plastic accumulation) through feedback from Purok leaders and Barangay Health Workers (BHWs).
        2. **Activity Design & Proposal Formulation:** The relevant committee (e.g., *Committee on Environmental Protection, Sanitation & Health*) prepares the detailed Project Activity Proposal specifying objectives, target zones, participant headcount, logistics, and budget breakdown.
        3. **Barangay Assembly Presentation:** The proposed priority project is presented during the semi-annual Barangay Assembly (March or October) for community feedback and social consensus.

        ### ⚖️ Phase 2: Sangguniang Barangay Deliberation & Statutory Resolution
        1. **Committee Referral:** The proposed Activity Design is referred to the Committee on Appropriations and the Committee on Environment.
        2. **Enactment of Barangay Resolution:** The Sangguniang Barangay formally passes a **Resolution** approving the project design, operational timetable, and community mobilization protocol.
        3. **Budget Allocation & AIP Integration:** The required funds are certified by the Barangay Treasurer and charged against:
           - **20% Barangay Development Fund (BDF)**
           - **Solid Waste Management Fund** (under RA 9003)
           - **10% Sangguniang Kabataan (SK) Fund** (for youth-led clean-ups)
           - **Barangay Disaster Risk Reduction and Management Fund (BDRRMF)** (if mitigating flood hazards)

        ### 📢 Phase 3: Public Publishing & Volunteer Mobilization
        Under the **DILG Full Disclosure Policy** and Republic Act No. 9418 (Volunteer Act of 2007), project details and calls for volunteers must be publicly disseminated:
        1. **Multi-Channel Publishing:**
           - **Barangay Transparency Board:** Posted visibly outside the Barangay Hall.
           - **Official Social Media Channels:** Published on the verified Barangay Facebook page with clear infographics detailing assembly time, target puroks, and safety instructions.
           - **Traditional "Bandilyo":** Public address broadcasts and megaphone announcements deployed through Purok leaders and Tanods.
        2. **Civil Society & Youth Mobilization:** Formal invitation letters sent to 4Ps parent-leaders, Boy/Girl Scouts, homeowners' associations (HOAs), church youth ministries, and university NSTP (National Service Training Program) coordinators.
        3. **Volunteer Registration & Profiling:** Pre-registration to monitor expected participant numbers, identify minors requiring parental consent, and arrange adequate food rations and safety gear.

        ### 🧹 Phase 4: Operational Execution & Safety Protocol (e.g. Oplan Kalinisan Drive)
        1. **Pre-Deployment Safety Briefing:**
           - Volunteers assemble at the Barangay Hall or designated covered court.
           - Safety orientation led by BDRRMC/Kagawad on hazard handling (broken glass, needles, biological waste, deep water).
           - Health screening by Barangay Health Workers (blood pressure check for seniors).
        2. **Distribution of Personal Protective Equipment (PPE):**
           - Heavy-duty rubber gloves, safety tongs, boots, dust masks, and color-coded garbage bags.
        3. **Zone Deployment & Tanod Escort:** Teams dispatched into designated clusters, each supervised by an assigned Kagawad or Purok leader, with Tanods directing traffic on public roadways.
        4. **Segregation at Source (RA 9003 Mandate):**
           - **Biodegradable (Nabubulok):** Leaves, organic matter routed to the Barangay composting facility.
           - **Recyclable (Di-nabubulok pero Mapapakinabangan):** Plastics, PET bottles, glass, metals routed to the Materials Recovery Facility (MRF).
           - **Residuals (Di-nabubulok):** Soiled materials collected for city/municipal sanitary landfill hauling.
           - **Special/Hazardous Waste:** E-waste, batteries, medical supplies stored in designated containment barrels.

        ### 📊 Phase 5: Post-Activity Documentation, Hauling & Liquidation
        1. **Waste Weighing & Hauling:** All collected waste is measured at the Barangay MRF and loaded into municipal compactors or authorized haulers.
        2. **Financial Liquidation (COA Rules):** The Barangay Treasurer prepares the official liquidation report compliant with Commission on Audit (COA) Circulars:
           - Official Receipts (ORs) for purchased snacks, trash bags, brooms, and first-aid supplies.
           - Signed participant attendance sheets and procurement inspection reports.
        3. **DILG Reporting:** Completion report filed with the DILG City/Municipal Local Government Operations Officer (MLGOO) under the *Kalinisan sa Bagong Pilipinas* program.
        4. **Volunteer Recognition:** Distribution of Certificates of Volunteerism and acknowledgement during the succeeding Barangay Assembly.

        ---

        ## 3. Visual Workflow Diagram

        ```text
        [Community Consultation / Purok Needs]
                      │
                      ▼
        [Activity Design & Committee Proposal]
                      │
                      ▼
        [Sangguniang Barangay Resolution & AIP Budget Allocation]
                      │
                      ▼
        [Public Notice (Transparency Board, FB, Bandilyo) & Volunteer Drive]
                      │
                      ▼
        [On-Site Safety Briefing + PPE Distribution + Tanod Traffic Escort]
                      │
                      ▼
        [Execution: Segregation at Source (Biodegradable / Recyclable / Residual)]
                      │
                      ▼
        [MRF Processing + COA Financial Liquidation + DILG Kalinisan Report]
        ```

        ---

        ## 4. Key Statutory Distinctions for Exams & Governance Practice

        | Legal Concept | Statutory Definition | Practical Application in Projects |
        | :--- | :--- | :--- |
        | **Barangay Ordinance** | Local law enacted with penal sanctions or permanent rule-making power. | Mandatory waste segregation with fines for illegal dumping (Anti-Littering Ordinance). |
        | **Barangay Resolution** | Declaration of legislative sentiment or temporary administrative authority. | Approves the implementation and budget of a single clean-up activity or event. |
        | **Barangay Development Plan (BDP)** | Multi-year blueprint of socio-economic priorities. | Ensures projects align with long-term infrastructure and sanitation roadmaps. |
        | **Annual Investment Program (AIP)** | Annual list of funded projects derived from the BDP. | Mandatory prerequisite before public funds can be disbursed by the treasurer. |

        ---

        ## 5. High-Yield Review Takeaways

        - **RA 7160 Sec. 397:** Barangay Assembly must convene at least twice a year to maintain participatory democracy.
        - **RA 9003 Sec. 32:** Mandates each barangay or cluster of barangays to establish an active Materials Recovery Facility (MRF).
        - **RA 9418 Sec. 12:** Protects volunteer rights and mandates host organizations to ensure volunteer safety, orientation, and appropriate recognition.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildLawAndJurisprudenceResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        # ⚖️ Legal Principles & Jurisprudence Guide: [SUBJECT]

        **Discipline:** Constitutional Law, Civil Jurisprudence & Public Administration  
        **Framework:** The 1987 Constitution of the Republic of the Philippines and Established Supreme Court Doctrines.

        ---

        ## 1. Foundational Pillars of Public & Civil Law

        ### The Three Inherent Powers of the State
        Every sovereign state exercises three fundamental, plenary powers that exist independently of constitutional grant:
        1. **Police Power:** The power of the state to enact laws promoting public health, safety, morals, and general welfare. Considered the most pervasive and least limitable power.
        2. **Power of Eminent Domain:** The authority to expropriate private property for public use upon payment of just compensation.
        3. **Power of Taxation:** The power to impose revenue-generating charges on persons, property, and transactions to fund governmental operations.

        ---

        ## 2. Due Process of Law (Article III, Section 1)
        No person shall be deprived of life, liberty, or property without due process of law, nor shall any person be denied the equal protection of the laws.

        ### Substantive vs. Procedural Due Process
        - **Substantive Due Process:** Inquires whether the statute itself is fair, reasonable, and enacted in pursuit of a legitimate governmental objective without being arbitrary or oppressive.
        - **Procedural Due Process:** Mandates notice and a fair opportunity to be heard before an impartial and competent tribunal (*The cardinal primary requirements of administrative due process* - Ang Tibay v. CIR).

        ---

        ## 3. Law of Obligations & Contracts (Civil Code)
        - **Sources of Obligations (Art. 1157):**
          1. Law (*ex lege*)
          2. Contracts (*ex contractu*)
          3. Quasi-contracts (*negotiorum gestio* and *solutio indebiti*)
          4. Delicts / Crimes (*ex delicto*)
          5. Quasi-delicts / Torts (*culpa aquiliana*)
        - **Essential Requisites of a Valid Contract (Art. 1318):**
          1. Consent of the contracting parties
          2. Object certain which is the subject matter
          3. Cause or consideration of the obligation

        ---

        ## 4. Statutory Construction & Latin Maxims
        | Maxim | Translation / Legal Meaning | Applied Rule |
        | :--- | :--- | :--- |
        | *Dura lex sed lex* | The law may be harsh, but it is the law. | Courts must apply clear statutes without equitable modification. |
        | *Ignorantia legis non excusat* | Ignorance of the law excuses no one. | All persons are conclusively presumed to know promulgated laws. |
        | *Salus populi est suprema lex* | The welfare of the people is the supreme law. | Police power justification for civic health and safety regulations. |
        | *Expressio unius est exclusio alterius* | The express mention of one implies exclusion of others. | Restricts statutory interpretation to enumerated categories. |

        ---

        ## 5. High-Yield Exam Takeaways
        - In statutory interpretation, the **Plain Meaning Rule (Verba Legis)** governs when text is clear and unambiguous.
        - Administrative bodies exercising quasi-judicial functions must provide substantial evidence (*such relevant evidence as a reasonable mind might accept as adequate to support a conclusion*).
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildEconomicsAndAccountingResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        # 📊 Economics & Financial Accounting Master Guide: [SUBJECT]

        **Core Fields:** Financial Accounting, Microeconomics & Macroeconomic Analysis  
        **Standards:** Generally Accepted Accounting Principles (GAAP) & International Financial Reporting Standards (IFRS).

        ---

        ## 1. The Fundamental Accounting Architecture

        ### The Accounting Equation
        $$\text{Assets} = \text{Liabilities} + \text{Owner's Equity}$$

        - **Assets:** Economic resources owned or controlled that provide probable future economic benefits (Cash, Accounts Receivable, Inventory, Equipment).
        - **Liabilities:** Present obligations arising from past transactions to be settled via asset transfer or service provision (Accounts Payable, Notes Payable).
        - **Owner's Equity (Net Worth):** Residual interest in assets after deducting liabilities (Capital, Retained Earnings minus Drawings/Dividends).

        ### Double-Entry Bookkeeping: The Debit & Credit Matrix
        | Account Type | Normal Balance | Increases Recorded As | Decreases Recorded As |
        | :--- | :--- | :--- | :--- |
        | **Assets** | Debit | **Debit (+)** | Credit (-) |
        | **Expenses** | Debit | **Debit (+)** | Credit (-) |
        | **Liabilities** | Credit | **Credit (+)** | Debit (-) |
        | **Equity / Capital** | Credit | **Credit (+)** | Debit (-) |
        | **Revenues / Income** | Credit | **Credit (+)** | Debit (-) |

        > **Golden Rule:** In every transaction, total Debits must exactly equal total Credits.

        ---

        ## 2. Microeconomics: Supply, Demand & Elasticity

        - **Law of Demand:** Ceteris paribus, as price increases, quantity demanded decreases (inverse relationship).
        - **Law of Supply:** Ceteris paribus, as price increases, quantity supplied increases (direct relationship).
        - **Price Elasticity of Demand ($E_d$):**
          $$E_d = \frac{\% \Delta Q_d}{\% \Delta P}$$
          - $|E_d| > 1$: Elastic (consumers are sensitive to price adjustments).
          - $|E_d| < 1$: Inelastic (necessities; consumers maintain consumption regardless of price).
          - $|E_d| = 1$: Unit elastic.

        ---

        ## 3. Macroeconomics: Output, Inflation & Policy Levers

        ### Gross Domestic Product (Expenditure Approach)
        $$Y = C + I + G + (X - M)$$
        Where $C$ = Consumption, $I$ = Investment, $G$ = Government Spending, and $(X - M)$ = Net Exports.

        ### Fiscal Policy vs. Monetary Policy
        - **Fiscal Policy (Government / Treasury):** Taxes and government spending used to influence aggregate demand.
        - **Monetary Policy (Central Bank):** Money supply management, interest rates (overnight repo rate), and reserve requirements to control inflation and currency stability.

        ---

        ## 4. High-Yield Exam Pitfalls
        - **Accrual vs. Cash Accounting:** Under GAAP/IFRS accrual accounting, revenue is recognized when *earned* (performance obligation satisfied), not when cash is received. Expenses are recognized when *incurred* (Matching Principle).
        - **Depreciation:** Is an allocation of cost over useful life, NOT a valuation method or a cash reserve fund.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildHealthSciencesResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        # 🩺 Clinical Health Sciences & Nursing Guide: [SUBJECT]

        **Domain:** Nursing Process, Clinical Procedures, Pharmacology & Human Physiology.

        ---

        ## 1. The Nursing Process (ADPIE)

        The clinical problem-solving framework used to deliver individualized, safe, and holistic patient care:
        1. **Assessment (A):** Systematic collection of subjective data (patient statements, symptoms) and objective data (vital signs, laboratory values, physical examination findings).
        2. **Diagnosis (D):** Identification of human response to actual or potential health problems using standardized NANDA-I taxonomy.
        3. **Planning (P):** Setting SMART goals (Specific, Measurable, Achievable, Relevant, Time-bound) and prioritizing interventions (Maslow's Hierarchy of Needs).
        4. **Implementation (I):** Executing nursing interventions, administering prescribed medications, and providing patient education.
        5. **Evaluation (E):** Comparing patient progress against expected outcomes and adjusting the care plan accordingly.

        ---

        ## 2. Vital Signs: Normal Adult Reference Values

        | Vital Sign | Normal Adult Range | Clinical Term for Low | Clinical Term for High |
        | :--- | :--- | :--- | :--- |
        | **Blood Pressure (BP)** | 90/60 to 120/80 mmHg | Hypotension (< 90/60) | Hypertension (≥ 130/80) |
        | **Heart Rate (HR)** | 60 - 100 beats/min | Bradycardia (< 60 bpm) | Tachycardia (> 100 bpm) |
        | **Respiratory Rate (RR)** | 12 - 20 breaths/min | Bradypnea (< 12 bpm) | Tachypnea (> 20 bpm) |
        | **Temperature** | 36.5°C - 37.5°C (Oral) | Hypothermia (< 35.0°C) | Hyperthermia / Pyrexia (> 38.0°C) |
        | **Pulse Oximetry ($SpO_2$)** | 95% - 100% room air | Hypoxemia (< 90%) | Hyperoxia |

        ---

        ## 3. Principles of Pharmacology

        - **Pharmacokinetics (What the Body Does to the Drug - ADME):**
          - **Absorption:** Entry into bloodstream.
          - **Distribution:** Transport to target tissues across physiological barriers.
          - **Metabolism:** Biotransformation (primarily hepatic cytochrome P450 enzymes).
          - **Excretion:** Elimination (primarily renal filtration and biliary clearance).
        - **Pharmacodynamics (What the Drug Does to the Body):**
          - **Agonist:** Activates receptor to elicit physiological response.
          - **Antagonist:** Binds receptor without activation, blocking agonist action.
        - **The Six Rights of Medication Administration:**
          1. Right Patient (verify two identifiers)
          2. Right Medication (check label three times)
          3. Right Dose
          4. Right Route (oral, IV, IM, SC, sublingual)
          5. Right Time
          6. Right Documentation

        ---

        ## 4. Infection Control & Safety Precautions
        - **Standard Precautions:** Hand hygiene before/after patient contact; PPE use when encountering blood, body fluids, non-intact skin.
        - **Donning PPE Sequence:** Gown → Mask/Respirator → Goggles/Face Shield → Gloves.
        - **Doffing PPE Sequence:** Gloves → Goggles → Gown → Mask (Gloves and gown are considered most contaminated).
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildSystemsAndNetworkingResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        return """
        # 💻 Computer Systems, Operating Systems & Networking: [SUBJECT]

        **Domain:** Computer Science, System Architecture, Concurrency & Network Protocols.

        ---

        ## 1. Operating Systems: Process Management & Concurrency

        ### Process vs. Thread
        - **Process:** An executing instance of a program with its own dedicated virtual address space, memory pages, file descriptors, and security context.
        - **Thread:** The smallest sequence of programmed instructions managed independently by the scheduler. Threads within the same process share code, data, and open files, but retain independent program counters, registers, and stack memory.

        ### The Four Coffman Conditions for Deadlock
        A deadlock occurs if and only if all four conditions hold simultaneously:
        1. **Mutual Exclusion:** At least one resource must be held in a non-shareable mode.
        2. **Hold and Wait:** A process holding at least one resource is waiting to acquire additional resources held by others.
        3. **No Preemption:** Resources cannot be forcibly seized; they are released only voluntarily.
        4. **Circular Wait:** A closed chain of processes exists where each process waits for a resource held by the next.

        ---

        ## 2. Virtual Memory & Paging Architecture
        - **Page Table:** Maps virtual addresses generated by the CPU to physical RAM frames.
        - **Translation Lookaside Buffer (TLB):** Hardware associative cache reducing virtual address translation latency.
        - **Page Fault:** Hardware trap triggered when a requested virtual page is not currently resident in physical memory, requiring disk retrieval.

        ---

        ## 3. Computer Networking & The OSI Model

        | OSI Layer | Protocol Data Unit (PDU) | Primary Protocols / Standards | Key Responsibility |
        | :--- | :--- | :--- | :--- |
        | **7. Application** | Data | HTTP, HTTPS, DNS, SSH, SMTP | End-user interface and application data. |
        | **6. Presentation**| Data | TLS/SSL, JSON, JPEG | Data encryption, compression, and formatting. |
        | **5. Session**     | Data | RPC, NetBIOS | Establishing and maintaining connections. |
        | **4. Transport**   | Segment (TCP) / Datagram (UDP) | TCP, UDP | End-to-end transport, port numbers, flow control. |
        | **3. Network**     | Packet | IP (IPv4/IPv6), ICMP, BGP | Logical addressing, routing across subnets. |
        | **2. Data Link**   | Frame | Ethernet, Wi-Fi (802.11), ARP | Physical MAC addressing, node-to-node transfer. |
        | **1. Physical**    | Bits | Fiber, Copper, Radio RF | Transmission of raw electrical/optical bitstream. |

        ### The TCP 3-Way Handshake
        ```text
        Client                        Server
          │                             │
          │─────── SYN (seq=x) ────────>│   1. Client initiates connection
          │                             │
          │<── SYN-ACK (seq=y, ack=x+1)─│   2. Server acknowledges & responds
          │                             │
          │─────── ACK (ack=y+1) ──────>│   3. Client confirms connection established
          │                             │
        [ Connection Established - Bidirectional Data Stream Open ]
        ```

        ---

        ## 4. High-Yield Networking Distinctions
        - **TCP vs. UDP:** TCP is connection-oriented, reliable (guaranteed delivery via ACKs and retransmissions), ordered, and flow-controlled. UDP is connectionless, unreliable, unordered, lightweight, and prioritized for low latency (VoIP, DNS, gaming).
        - **DNS Resolution:** Recursive resolver checks local cache → Root Name Server → TLD Server (.com/.edu) → Authoritative Name Server → IP Address.
        """.Replace("[SUBJECT]", subject);
    }

    private static string BuildGeneralAcademicResponse(string prompt, string topic)
    {
        var subject = !string.IsNullOrWhiteSpace(topic) ? topic : CleanQuery(prompt);
        var inquiryContext = ExtractCoreInquiry(prompt, subject);

        return """
        # 📚 Comprehensive Academic Guide: [SUBJECT]

        **Inquiry Focus:** [INQUIRY]  
        **Academic Level:** Higher Education / Comprehensive Curriculum Review  
        **Pedagogical Objective:** Rigorous mastery of foundational concepts, underlying mechanics, step-by-step methodologies, real-world case analysis, and high-yield examination readiness.

        ---

        ## 1. Executive Overview & Disciplinary Scope

        **[SUBJECT]** is a foundational concept within this disciplinary domain. At its core, it establishes the principles, rules, and methodological workflows required to analyze, model, and execute solutions to complex problems.

        ### Key Academic Pillars:
        1. **Systemic Consistency:** Every component within **[SUBJECT]** operates under well-defined constraints and formal axioms to ensure reproducible outcomes.
        2. **Hierarchical Decomposition:** High-level abstractions are systematically decomposed into modular sub-problems, minimizing cognitive complexity and isolating points of failure.
        3. **Deterministic Transformation:** Specific inputs and conditions undergo disciplined operations to yield predictable, verifiable results across theoretical and applied environments.

        ---

        ## 2. Core Theoretical Mechanics & Step-by-Step Methodology

        To master **[SUBJECT]** academically and practically, follow this disciplined five-phase process:

        ### 🔍 Phase 1: Environmental Assessment & Boundary Conditions
        - Identify all given variables, baseline constraints, and environmental preconditions.
        - Isolate independent variables from dependent variables to avoid conflating causal drivers with correlation.
        - Verify unit dimensions, scope boundaries, and operational assumptions before executing any transformation.

        ### ⚙️ Phase 2: Selection of Governing Rules & Principles
        - Map observed conditions to the appropriate theoretical framework, statutory rule, or mathematical model.
        - Establish preconditions: verify that all prerequisite assumptions are satisfied before applying the primary transformation.

        ### 🔄 Phase 3: Systematic Execution & Processing
        - Execute intermediate transformations sequentially rather than combining steps arbitrarily.
        - Document each transitional state to maintain complete auditability and error traceability.
        - Account for environmental friction, resource limits, or real-world damping factors that cause deviations from ideal models.

        ### 📊 Phase 4: Verification, Cross-Checking & Validation
        - Test against standard boundary limits: evaluate behavior at minimum, nominal, and extreme capacity thresholds.
        - Check conservation laws (mass, energy, value, or state parity) to verify internal coherence.

        ### 📈 Phase 5: Synthesis, Reporting & Iterative Optimization
        - Interpret final results in context with baseline objectives.
        - Formulate corrective feedback loops to optimize future performance or refine theoretical models.

        ---

        ## 3. Real-World Applied Case Study

        Consider a practical scenario illustrating **[SUBJECT]** in an operational setting:
        - **Scenario Setup:** An organization or practitioner faces a challenging problem requiring structured intervention under tight constraints.
        - **Diagnostic Action:** The team conducts a rigorous initial assessment, identifying key bottlenecks and selecting the governing principles of **[SUBJECT]**.
        - **Operational Execution:** By applying the step-by-step methodology outlined above, resources are directed toward primary drivers while mitigating secondary risks.
        - **Outcome & Analysis:** The system stabilizes, meeting required performance criteria while establishing a documented baseline for subsequent iterations.

        ---

        ## 4. High-Yield Distinctions & Conceptual Comparison Matrix

        | Dimension | Theoretical / Ideal Model | Applied / Real-World Implementation |
        | :--- | :--- | :--- |
        | **Primary Focus** | Absolute precision and mathematical or statutory perfection. | Pragmatic optimization balancing constraints, time, and resources. |
        | **Assumption Handling** | Assumes frictionless conditions, complete data, and static states. | Dynamically adapts to incomplete data, stochastic variance, and external shocks. |
        | **Error Management** | Zero-tolerance theoretical proofs and strict invariants. | Robust error handling, defensive guards, and graceful degradation. |
        | **Evaluation Metric** | Theoretical correctness and logical elegance. | Measurable impact, reliability, and reproducible outcomes. |

        ---

        ## 5. Common Exam Pitfalls & Misconceptions

        - ⚠️ **Trap 1: Conflating Terminology:** Confusing **[SUBJECT]** with superficially similar concepts. Always identify the distinguishing operational mechanism.
        - ⚠️ **Trap 2: Ignoring Boundary Conditions:** Forgetting that theoretical rules hold only within their defined domain of validity. Testing edge cases (0, 1, infinity, null) prevents common calculation errors.
        - ⚠️ **Trap 3: Skipping Intermediate Validation:** Attempting to jump directly from input parameters to final conclusions without verifying prerequisite steps.

        ---

        ## 6. Active Recall & Self-Assessment Checklist

        - [ ] Can you define **[SUBJECT]** in one concise sentence without using circular terminology?
        - [ ] Can you list the 5 sequential phases required to implement or evaluate this concept?
        - [ ] Can you identify at least two conditions under which standard assumptions break down?
        - [ ] Can you explain the difference between the theoretical model and its real-world implementation?
        """.Replace("[SUBJECT]", subject).Replace("[INQUIRY]", inquiryContext);
    }

    private static string ExtractCoreInquiry(string prompt, string subject)
    {
        if (string.IsNullOrWhiteSpace(prompt)) return subject;
        var clean = Regex.Replace(prompt, @"^(?:what\s+(?:is|are)\s+(?:the\s+)?(?:actual\s+)?(?:process\s+of\s+)?|how\s+to\s+|explain\s+(?:the\s+)?|tell\s+me\s+about\s+)", "", RegexOptions.IgnoreCase).Trim();
        if (clean.EndsWith("?", StringComparison.Ordinal)) clean = clean.TrimEnd('?').Trim();
        if (clean.Length == 0) return subject;
        if (clean.Length > 80) clean = clean.Substring(0, 80).Trim() + "...";
        return char.ToUpperInvariant(clean[0]) + clean.Substring(1);
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
