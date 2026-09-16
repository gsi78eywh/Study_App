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

        var existing = await _context.Courses.AnyAsync(c => c.UserId == userId.Value, cancellationToken);
        if (existing)
        {
            return Ok(new { success = true, message = "Workspace already initialized." });
        }

        var bioCourse = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userId.Value,
            Code = "BIO-101",
            Name = "General Cellular Biology & Genetics",
            ColorHex = "#10B981",
            ExamDate = DateTime.UtcNow.AddDays(5),
            ExamTitle = "Midterm Examination",
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

        _context.Courses.Add(bioCourse);
        await _context.SaveChangesAsync(cancellationToken);

        return Ok(new { success = true, message = "Starter Demo Pack loaded successfully." });
    }

    [HttpGet]
    public async Task<IActionResult> GetCourses(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var courses = await _context.Courses
            .Where(course => course.UserId == userId.Value)
            .OrderBy(course => course.Name)
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
