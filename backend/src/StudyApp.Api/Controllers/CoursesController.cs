using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;

namespace StudyApp.Api.Controllers;

public record CreateCourseRequest(string Code, string Name, string? ColorHex = null, DateTime? ExamDate = null, string? ExamTitle = null);
public record UpdateCourseRequest(string Code, string Name, string? ColorHex = null, DateTime? ExamDate = null, string? ExamTitle = null);
public record UpdateCourseExamRequest(DateTime? ExamDate, string? ExamTitle);

[ApiController]
[Route("api/v1/courses")]
[Authorize]
public sealed class CoursesController : ControllerBase
{
    private readonly IApplicationDbContext _context;

    public CoursesController(IApplicationDbContext context) => _context = context;

    [HttpPost("demo-pack")]
    public async Task<IActionResult> LoadDemoPack(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var provisioned = await ProvisionStarterPackAsync(userId.Value, _context, cancellationToken);
        if (!provisioned)
        {
            return Ok(new { success = true, message = "Workspace already initialized." });
        }

        return Ok(new { success = true, message = "Starter Demo Pack loaded successfully." });
    }

    public static async Task<bool> ProvisionStarterPackAsync(Guid userId, IApplicationDbContext context, CancellationToken cancellationToken = default)
    {
        var existing = await context.Courses.AnyAsync(c => c.UserId == userId, cancellationToken);
        if (existing)
        {
            return false;
        }

        // Course 1: BIO-101 General Cellular Biology & Genetics
        var bioCourse = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Code = "BIO-101",
            Name = "General Cellular Biology & Genetics",
            ColorHex = "#10B981",
            ExamDate = DateTime.UtcNow.AddDays(5),
            ExamTitle = "Midterm Examination",
            Units = 3.0f,
            TargetGrade = 1.0f,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        var bioSet = new StudySet
        {
            Id = Guid.NewGuid(),
            CourseId = bioCourse.Id,
            Title = "Photosynthesis & Cellular Respiration",
            Description = "Exam mastery deck covering light reactions, the Calvin cycle, and mitochondrial ATP synthesis.",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        var q1 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = bioSet.Id,
            Type = QuestionType.MultipleChoice,
            Prompt = "During the light-dependent reactions of photosynthesis, what is the primary role of water photolysis?",
            HintsJson = "[\"Consider what resupplies lost electrons to the photosystem.\",\"Oxygen is released as a byproduct.\"]",
            Explanation = "Photolysis splits water into protons, electrons, and O2 to resupply photo-excited chlorophyll.",
            Difficulty = 2,
            SortOrder = 1
        };
        q1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q1.Id, OptionText = "Replenish electrons in photo-excited chlorophyll", IsCorrect = true });
        q1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q1.Id, OptionText = "Provide carbon atoms for glucose synthesis", IsCorrect = false, DistractorRationale = "Carbon is supplied by carbon dioxide in the Calvin cycle." });
        q1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q1.Id, OptionText = "Directly phosphorylate ADP without a proton gradient", IsCorrect = false, DistractorRationale = "ATP is generated via ATP synthase and the proton gradient." });
        q1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q1.Id, OptionText = "Cleave RuBisCO enzyme complexes", IsCorrect = false, DistractorRationale = "RuBisCO operates in the stroma and is not cleaved by water." });

        var q2 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = bioSet.Id,
            Type = QuestionType.TrueFalse,
            Prompt = "True or False: Glycolysis requires molecular oxygen to generate pyruvate and net 2 ATP.",
            HintsJson = "[\"Glycolysis is an anaerobic pathway.\"]",
            Explanation = "Glycolysis occurs in the cytoplasm and operates anaerobically without oxygen.",
            Difficulty = 1,
            SortOrder = 2
        };
        q2.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q2.Id, OptionText = "False", IsCorrect = true });
        q2.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q2.Id, OptionText = "True", IsCorrect = false });

        var q3 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = bioSet.Id,
            Type = QuestionType.Identification,
            Prompt = "Identify the enzyme in the inner mitochondrial membrane that utilizes proton motive force to synthesize ATP.",
            HintsJson = "[\"It operates like a molecular turbine.\"]",
            Explanation = "ATP synthase phosphorylates ADP into ATP as H+ protons flow down their gradient.",
            Difficulty = 2,
            SortOrder = 3
        };
        q3.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q3.Id, OptionText = "ATP Synthase", IsCorrect = true });

        var q4 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = bioSet.Id,
            Type = QuestionType.Identification,
            Prompt = "What is the primary function of the Calvin Cycle (Light-Independent Reactions)?",
            Explanation = "To fix inorganic atmospheric carbon dioxide into 3-carbon sugars (G3P) using ATP and NADPH produced by the light reactions.",
            Difficulty = 2,
            SortOrder = 4
        };
        q4.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q4.Id, OptionText = "Fix carbon dioxide into glucose precursors using ATP and NADPH", IsCorrect = true });

        bioSet.Questions.Add(q1);
        bioSet.Questions.Add(q2);
        bioSet.Questions.Add(q3);
        bioSet.Questions.Add(q4);
        bioCourse.StudySets.Add(bioSet);

        var bioNote = new NotebookPage
        {
            Id = Guid.NewGuid(),
            CourseId = bioCourse.Id,
            Title = "Lecture 1: Photosynthesis & Cellular Energetics",
            ContentMarkdown = @"# Photosynthesis & Cellular Energetics

## 1. Overview
Photosynthesis transforms solar photon energy into stable chemical bonds (glucose), which cellular respiration subsequently metabolizes to generate ATP.

## 2. Key Stages
- **Light Reactions**: Occur in thylakoid membranes. Photolysis of H2O supplies electrons to photosystem II, releasing O2 and generating ATP + NADPH.
- **Calvin Cycle (Dark Reactions)**: Occurs in the stroma. RuBisCO fixes atmospheric CO2 into G3P (3-carbon sugar).
- **Cellular Respiration**: Glycolysis (cytosol, anaerobic) -> Krebs Cycle (mitochondrial matrix) -> Oxidative Phosphorylation (inner membrane via ATP Synthase).

## 3. High-Yield Retention Rules
1. *Glycolysis is anaerobic* and produces a net of 2 ATP and 2 NADH per glucose.
2. *ATP Synthase* utilizes the proton motive force (chemiosmosis) across the inner mitochondrial membrane.",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        bioCourse.NotebookPages.Add(bioNote);

        // Course 2: CS-101 Introduction to Computer Science & C#
        var csCourse = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Code = "CS-101",
            Name = "Introduction to Computer Science & C#",
            ColorHex = "#6366F1",
            ExamDate = DateTime.UtcNow.AddDays(12),
            ExamTitle = "C# & OOP Final Examination",
            Units = 3.0f,
            TargetGrade = 1.0f,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        var csSet = new StudySet
        {
            Id = Guid.NewGuid(),
            CourseId = csCourse.Id,
            Title = "C# Fundamentals & Object-Oriented Programming",
            Description = "Comprehensive mastery deck on .NET CLR architecture, value vs reference types, OOP pillars, and LINQ syntax.",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        var csq1 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = csSet.Id,
            Type = QuestionType.MultipleChoice,
            Prompt = "What is the primary role of the Common Language Runtime (CLR) in the .NET ecosystem?",
            HintsJson = "[\"Think about what executes Intermediate Language (IL) and manages memory.\",\"It includes garbage collection and JIT compilation.\"]",
            Explanation = "The CLR provides an execution environment that handles JIT compilation, garbage collection, thread management, and type safety for .NET applications.",
            Difficulty = 2,
            SortOrder = 1
        };
        csq1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq1.Id, OptionText = "Manage code execution, garbage collection, and JIT compilation", IsCorrect = true });
        csq1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq1.Id, OptionText = "Directly translate C# source code into machine code at authoring time", IsCorrect = false, DistractorRationale = "Roslyn compiles C# into CIL (Common Intermediate Language), which the CLR JIT-compiles at runtime." });
        csq1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq1.Id, OptionText = "Serve as a relational database query engine", IsCorrect = false, DistractorRationale = "The CLR is a runtime execution environment, not a database." });
        csq1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq1.Id, OptionText = "Provide an exclusively client-side web browser rendering engine", IsCorrect = false, DistractorRationale = "Web browsers render HTML/CSS/JS, whereas CLR executes managed .NET assemblies." });

        var csq2 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = csSet.Id,
            Type = QuestionType.TrueFalse,
            Prompt = "True or False: In C#, primitive types like int, bool, and double are reference types stored on the managed heap by default.",
            HintsJson = "[\"Consider whether structs and primitives are value types or reference types.\"]",
            Explanation = "Primitive numeric and boolean types are value types (structs) that directly contain their data and are typically allocated on the stack unless boxed.",
            Difficulty = 1,
            SortOrder = 2
        };
        csq2.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq2.Id, OptionText = "False", IsCorrect = true });
        csq2.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq2.Id, OptionText = "True", IsCorrect = false });

        var csq3 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = csSet.Id,
            Type = QuestionType.MultipleChoice,
            Prompt = "Which .NET language feature enables querying in-memory collections, databases, and XML using a consistent, declarative syntax?",
            HintsJson = "[\"It stands for Language Integrated Query.\"]",
            Explanation = "LINQ (Language Integrated Query) provides uniform query syntax across diverse data sources with compile-time type checking.",
            Difficulty = 1,
            SortOrder = 3
        };
        csq3.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq3.Id, OptionText = "LINQ (Language Integrated Query)", IsCorrect = true });
        csq3.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq3.Id, OptionText = "WPF (Windows Presentation Foundation)", IsCorrect = false, DistractorRationale = "WPF is a UI presentation framework." });
        csq3.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq3.Id, OptionText = "gRPC Remote Procedure Calls", IsCorrect = false, DistractorRationale = "gRPC is a high-performance network transport protocol." });
        csq3.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq3.Id, OptionText = "Entity Garbage Collector", IsCorrect = false, DistractorRationale = "Garbage collection manages memory, not query syntax." });

        var csq4 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = csSet.Id,
            Type = QuestionType.Identification,
            Prompt = "In C#, which keyword must be used in a derived class to provide a new implementation of a virtual or abstract base method?",
            HintsJson = "[\"It pairs with the virtual or abstract keyword on the parent class.\"]",
            Explanation = "The 'override' modifier is required to extend or modify the abstract or virtual implementation of an inherited method, property, or indexer.",
            Difficulty = 2,
            SortOrder = 4
        };
        csq4.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq4.Id, OptionText = "override", IsCorrect = true });

        var csq5 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = csSet.Id,
            Type = QuestionType.MultipleChoice,
            Prompt = "What C# statement or declaration ensures that an IDisposable resource (such as a FileStream or DbContext) is deterministically disposed when execution leaves its scope?",
            HintsJson = "[\"It automatically generates a try-finally block that calls Dispose().\"]",
            Explanation = "The 'using' statement or declaration guarantees that Dispose() is called on the IDisposable object even if an exception is thrown.",
            Difficulty = 2,
            SortOrder = 5
        };
        csq5.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq5.Id, OptionText = "using", IsCorrect = true });
        csq5.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq5.Id, OptionText = "finalize", IsCorrect = false, DistractorRationale = "Finalize is non-deterministic and executed by the garbage collector." });
        csq5.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq5.Id, OptionText = "lock", IsCorrect = false, DistractorRationale = "lock is used for thread synchronization, not deterministic resource disposal." });
        csq5.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = csq5.Id, OptionText = "checked", IsCorrect = false, DistractorRationale = "checked enables overflow checking for arithmetic operations." });

        csSet.Questions.Add(csq1);
        csSet.Questions.Add(csq2);
        csSet.Questions.Add(csq3);
        csSet.Questions.Add(csq4);
        csSet.Questions.Add(csq5);
        csCourse.StudySets.Add(csSet);

        var csNote = new NotebookPage
        {
            Id = Guid.NewGuid(),
            CourseId = csCourse.Id,
            Title = "Lecture 1: C# Architecture, Data Types & OOP Foundations",
            ContentMarkdown = @"# C# Architecture & Object-Oriented Programming

## 1. .NET Runtime Architecture
- **Roslyn Compiler**: Converts C# high-level source code into Common Intermediate Language (CIL/IL).
- **Common Language Runtime (CLR)**: The execution environment providing Just-In-Time (JIT) compilation from IL to native CPU instructions, memory management, garbage collection, and type verification.

## 2. Type System Fundamentals
- **Value Types**: Stored directly where declared (typically on the stack). Examples: `int`, `double`, `bool`, `struct`.
- **Reference Types**: Contain references (memory pointers) to data residing on the managed garbage-collected heap. Examples: `string`, `class`, arrays, delegates.

## 3. Core Object-Oriented Principles in C#
1. **Encapsulation**: Bundling state and behavior with access modifiers (`private`, `protected`, `public`, `internal`).
2. **Inheritance**: Subclassing with `:` syntax and single implementation inheritance.
3. **Polymorphism**: Dynamic method dispatch using `virtual` in the base class and `override` in the derived class.
4. **Abstraction**: Contract definition via `interface` and `abstract` classes.

## 4. Modern C# Features
- **LINQ**: Declarative data queries (`from x in list where x.Active select x`).
- **Resource Management**: Deterministic disposal with `using var resource = new Resource();`.",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        csCourse.NotebookPages.Add(csNote);

        context.Courses.Add(bioCourse);
        context.Courses.Add(csCourse);
        await context.SaveChangesAsync(cancellationToken);
        return true;
    }

    [HttpGet]
    public async Task<IActionResult> GetCourses(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var query = _context.Courses.Where(course => course.UserId == userId.Value);

        var totalCount = await query.CountAsync(cancellationToken);
        if (totalCount == 0)
        {
            var provisioned = await ProvisionStarterPackAsync(userId.Value, _context, cancellationToken);
            if (provisioned)
            {
                totalCount = await query.CountAsync(cancellationToken);
            }
        }

        var effectivePage = Math.Max(1, page);
        var effectivePageSize = Math.Clamp(pageSize, 1, 100);
        var totalPages = (int)Math.Ceiling(totalCount / (double)effectivePageSize);

        Response.Headers["X-Pagination-Total-Count"] = totalCount.ToString();
        Response.Headers["X-Pagination-Page"] = effectivePage.ToString();
        Response.Headers["X-Pagination-Page-Size"] = effectivePageSize.ToString();
        Response.Headers["X-Pagination-Total-Pages"] = totalPages.ToString();

        var courses = await query
            .OrderBy(course => course.Code)
            .ThenBy(course => course.Name)
            .Skip((effectivePage - 1) * effectivePageSize)
            .Take(effectivePageSize)
            .Select(course => new
            {
                course.Id,
                course.Code,
                course.Name,
                course.ColorHex,
                course.ExamDate,
                course.ExamTitle,
                course.CreatedAt,
                course.UpdatedAt,
                StudySetCount = course.StudySets.Count,
                QuestionCount = course.StudySets.SelectMany(set => set.Questions).Count(),
                StudySets = course.StudySets
                    .OrderByDescending(set => set.UpdatedAt ?? set.CreatedAt)
                    .Select(set => new
                    {
                        set.Id,
                        set.CourseId,
                        set.Title,
                        set.Description,
                        set.CreatedAt,
                        set.UpdatedAt,
                        QuestionCount = set.Questions.Count
                    })
            })
            .ToListAsync(cancellationToken);

        return Ok(courses);
    }

    [HttpPost]
    public async Task<IActionResult> CreateCourse([FromBody] CreateCourseRequest request, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();
        if (!TryValidate(request.Code, request.Name, request.ColorHex, out var error)) return BadRequest(new { message = error });

        var codeTrimmed = request.Code.Trim();
        var exists = await _context.Courses.AnyAsync(
            c => c.UserId == userId.Value && c.Code.ToLower() == codeTrimmed.ToLower(),
            cancellationToken);
        if (exists)
        {
            return BadRequest(new { message = $"A course with code '{codeTrimmed}' already exists." });
        }

        var now = DateTime.UtcNow;
        var course = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userId.Value,
            Code = codeTrimmed,
            Name = request.Name.Trim(),
            ColorHex = NormalizeColor(request.ColorHex),
            ExamDate = request.ExamDate,
            ExamTitle = request.ExamTitle?.Trim(),
            CreatedAt = now,
            UpdatedAt = now
        };
        _context.Courses.Add(course);
        await _context.SaveChangesAsync(cancellationToken);
        return Created($"/api/v1/courses/{course.Id}", new
        {
            id = course.Id,
            userId = course.UserId,
            code = course.Code,
            name = course.Name,
            colorHex = course.ColorHex,
            examDate = course.ExamDate,
            examTitle = course.ExamTitle,
            createdAt = course.CreatedAt,
            updatedAt = course.UpdatedAt,
            studySets = Array.Empty<object>()
        });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetCourseById(Guid id, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var course = await _context.Courses
            .Where(course => course.Id == id && course.UserId == userId.Value)
            .Select(course => new
            {
                course.Id,
                course.UserId,
                course.Code,
                course.Name,
                course.ColorHex,
                course.ExamDate,
                course.ExamTitle,
                course.CreatedAt,
                course.UpdatedAt,
                studySets = course.StudySets.Select(set => new
                {
                    set.Id,
                    set.CourseId,
                    set.Title,
                    set.Description,
                    set.CreatedAt,
                    set.UpdatedAt,
                    questionCount = set.Questions.Count
                }).ToList()
            })
            .SingleOrDefaultAsync(cancellationToken);

        if (course is null) return NotFound(new { message = "Course not found." });
        return Ok(course);
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> UpdateCourse(Guid id, [FromBody] UpdateCourseRequest request, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();
        if (!TryValidate(request.Code, request.Name, request.ColorHex, out var error)) return BadRequest(new { message = error });

        var course = await _context.Courses.SingleOrDefaultAsync(course => course.Id == id && course.UserId == userId.Value, cancellationToken);
        if (course is null) return NotFound(new { message = "Course not found." });

        course.Code = request.Code.Trim();
        course.Name = request.Name.Trim();
        course.ColorHex = NormalizeColor(request.ColorHex);
        course.ExamDate = request.ExamDate;
        course.ExamTitle = request.ExamTitle?.Trim();
        course.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync(cancellationToken);
        return Ok(course);
    }

    [HttpPut("{id:guid}/exam")]
    public async Task<IActionResult> UpdateCourseExam(Guid id, [FromBody] UpdateCourseExamRequest request, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var course = await _context.Courses.SingleOrDefaultAsync(c => c.Id == id && c.UserId == userId.Value, cancellationToken);
        if (course is null) return NotFound(new { message = "Course not found." });

        course.ExamDate = request.ExamDate;
        course.ExamTitle = string.IsNullOrWhiteSpace(request.ExamTitle) ? null : request.ExamTitle.Trim();
        course.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync(cancellationToken);
        return Ok(new { success = true, examDate = course.ExamDate, examTitle = course.ExamTitle });
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteCourse(Guid id, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var course = await _context.Courses
            .Include(c => c.StudySets)
                .ThenInclude(s => s.Questions)
                    .ThenInclude(q => q.Options)
            .Include(c => c.StudySets)
                .ThenInclude(s => s.Questions)
                    .ThenInclude(q => q.Rubrics)
            .Include(c => c.StudySets)
                .ThenInclude(s => s.SourceDocuments)
            .SingleOrDefaultAsync(course => course.Id == id && course.UserId == userId.Value, cancellationToken);
        if (course is null) return NotFound(new { message = "Course not found." });

        _context.Courses.Remove(course);
        await _context.SaveChangesAsync(cancellationToken);
        return NoContent();
    }

    [HttpGet("{id:guid}/studysets")]
    public async Task<IActionResult> GetStudySets(Guid id, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var courseExists = await _context.Courses.AnyAsync(course => course.Id == id && course.UserId == userId.Value, cancellationToken);
        if (!courseExists) return NotFound(new { message = "Course not found." });

        var studySets = await _context.StudySets
            .Where(set => set.CourseId == id)
            .OrderByDescending(set => set.UpdatedAt ?? set.CreatedAt)
            .Select(set => new
            {
                set.Id,
                set.CourseId,
                set.Title,
                set.Description,
                set.CreatedAt,
                set.UpdatedAt,
                QuestionCount = set.Questions.Count
            })
            .ToListAsync(cancellationToken);
        return Ok(studySets);
    }

    private Guid? GetUserId() => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;

    private static bool TryValidate(string? code, string? name, string? colorHex, out string? error)
    {
        if (string.IsNullOrWhiteSpace(code) || code.Trim().Length > 32)
        {
            error = "Course code is required and must be 32 characters or fewer.";
            return false;
        }
        if (string.IsNullOrWhiteSpace(name) || name.Trim().Length > 150)
        {
            error = "Course name is required and must be 150 characters or fewer.";
            return false;
        }
        if (!string.IsNullOrWhiteSpace(colorHex) && !System.Text.RegularExpressions.Regex.IsMatch(colorHex, "^#[0-9A-Fa-f]{6}$"))
        {
            error = "Color must be a six-digit hex value such as #4F46E5.";
            return false;
        }
        error = null;
        return true;
    }

    private static string NormalizeColor(string? colorHex) => string.IsNullOrWhiteSpace(colorHex) ? "#4F46E5" : colorHex.Trim().ToUpperInvariant();
}
