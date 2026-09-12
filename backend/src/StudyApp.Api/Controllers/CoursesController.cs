using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;

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
                QuestionCount = course.StudySets.SelectMany(set => set.Questions).Count()
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

        var now = DateTime.UtcNow;
        var course = new Course
        {
            Id = Guid.NewGuid(),
            UserId = userId.Value,
            Code = request.Code.Trim(),
            Name = request.Name.Trim(),
            ColorHex = NormalizeColor(request.ColorHex),
            CreatedAt = now,
            UpdatedAt = now
        };
        _context.Courses.Add(course);
        await _context.SaveChangesAsync(cancellationToken);
        return Created($"/api/v1/courses/{course.Id}", course);
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

        var course = await _context.Courses.SingleOrDefaultAsync(course => course.Id == id && course.UserId == userId.Value, cancellationToken);
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
