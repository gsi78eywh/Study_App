using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;

namespace StudyApp.Api.Controllers;

public record CreateCourseRequest(string Code, string Name, string? ColorHex = null);
public record UpdateCourseRequest(string Code, string Name, string? ColorHex = null);

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
        bioSet.Questions.Add(q1);

        var q2 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = bioSet.Id,
            Type = QuestionType.Identification,
            Prompt = "What specialized enzyme in the chloroplast stroma catalyzes the initial fixation of carbon dioxide to ribulose 1,5-bisphosphate (RuBP)?",
            HintsJson = "[\"Abbreviated with 7 letters (RuB...)\",\"Most abundant enzyme on Earth.\"]",
            Explanation = "RuBisCO (Ribulose-1,5-bisphosphate carboxylase-oxygenase) catalyzes the crucial initial carbon-fixing step.",
            Difficulty = 2,
            SortOrder = 2
        };
        q2.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q2.Id, OptionText = "RuBisCO", IsCorrect = true });
        bioSet.Questions.Add(q2);

        bioCourse.StudySets.Add(bioSet);
        _context.Courses.Add(bioCourse);

        var sampleNote = new NotebookPage
        {
            Id = Guid.NewGuid(),
            CourseId = bioCourse.Id,
            Title = "Photosynthesis: Light vs Dark Reactions Summary",
            ContentMarkdown = "# Photosynthesis Core Principles\n\n- **Light Reactions:** Thylakoid membrane. Uses H2O + photons -> ATP + NADPH + O2.\n- **Calvin Cycle:** Stroma. Uses CO2 + ATP + NADPH -> G3P (Glucose precursor).\n- **Key Rate Limiter:** RuBisCO temperature and CO2/O2 concentration ratio.",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        _context.NotebookPages.Add(sampleNote);

        await _context.SaveChangesAsync(cancellationToken);
        return Ok(new { success = true, courseId = bioCourse.Id, message = "Starter Demo Pack loaded successfully!" });
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
            createdAt = course.CreatedAt,
            updatedAt = course.UpdatedAt,
            studySets = Array.Empty<object>()
        });
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
        course.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync(cancellationToken);
        return Ok(course);
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
