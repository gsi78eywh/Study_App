using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Entities;

namespace StudyApp.Api.Controllers;

public record CreateNotebookRequest(Guid CourseId, string Title, string ContentMarkdown, string? Tags = null);
public record UpdateNotebookRequest(string Title, string ContentMarkdown, string? Tags = null);

[ApiController]
[Route("api/v1/notebooks")]
[Authorize]
public sealed class NotebooksController : ControllerBase
{
    private readonly IApplicationDbContext _context;

    public NotebooksController(IApplicationDbContext context)
    {
        _context = context;
    }

    [HttpGet]
    public async Task<IActionResult> GetNotes([FromQuery] Guid? courseId, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var query = _context.NotebookPages
            .Include(note => note.Course)
            .Where(note => note.Course != null && note.Course.UserId == userId.Value);

        if (courseId.HasValue && courseId.Value != Guid.Empty)
        {
            query = query.Where(n => n.CourseId == courseId.Value);
        }

        var notes = await query
            .OrderByDescending(n => n.UpdatedAt ?? n.CreatedAt)
            .Select(n => new
            {
                n.Id,
                n.CourseId,
                CourseCode = n.Course != null ? n.Course.Code : "GENERAL",
                CourseName = n.Course != null ? n.Course.Name : "General Notes",
                n.Title,
                Content = n.ContentMarkdown,
                ContentMarkdown = n.ContentMarkdown,
                Tags = "#Notes",
                n.CreatedAt,
                n.UpdatedAt
            })
            .ToListAsync(cancellationToken);

        return Ok(notes);
    }

    [HttpPost]
    public async Task<IActionResult> CreateNote([FromBody] CreateNotebookRequest request, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        if (request.CourseId == Guid.Empty || string.IsNullOrWhiteSpace(request.Title) || string.IsNullOrWhiteSpace(request.ContentMarkdown))
        {
            return BadRequest(new { message = "Course, title, and note content are required." });
        }

        if (request.Title.Trim().Length > 200)
        {
            return BadRequest(new { message = "Note title cannot exceed 200 characters." });
        }

        var ownsCourse = await _context.Courses.AnyAsync(course => course.Id == request.CourseId && course.UserId == userId.Value, cancellationToken);
        if (!ownsCourse) return NotFound(new { message = "Course not found." });

        var course = await _context.Courses.FirstOrDefaultAsync(c => c.Id == request.CourseId, cancellationToken);
        var now = DateTime.UtcNow;
        var note = new NotebookPage
        {
            Id = Guid.NewGuid(),
            CourseId = request.CourseId,
            Title = request.Title.Trim(),
            ContentMarkdown = request.ContentMarkdown,
            CreatedAt = now,
            UpdatedAt = now
        };

        _context.NotebookPages.Add(note);
        await _context.SaveChangesAsync(cancellationToken);

        return Created($"/api/v1/notebooks/{note.Id}", new
        {
            note.Id,
            note.CourseId,
            CourseCode = course?.Code ?? "GENERAL",
            CourseName = course?.Name ?? "General Notes",
            note.Title,
            Content = note.ContentMarkdown,
            ContentMarkdown = note.ContentMarkdown,
            Tags = request.Tags ?? "#Notes",
            note.CreatedAt,
            note.UpdatedAt
        });
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> UpdateNote(Guid id, [FromBody] UpdateNotebookRequest request, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        if (string.IsNullOrWhiteSpace(request.Title) || string.IsNullOrWhiteSpace(request.ContentMarkdown))
        {
            return BadRequest(new { message = "Note title and content are required." });
        }

        if (request.Title.Trim().Length > 200)
        {
            return BadRequest(new { message = "Note title cannot exceed 200 characters." });
        }

        var note = await _context.NotebookPages
            .Include(page => page.Course)
            .SingleOrDefaultAsync(page => page.Id == id && page.Course != null && page.Course.UserId == userId.Value, cancellationToken);

        if (note is null) return NotFound(new { message = "Note not found." });

        note.Title = request.Title.Trim();
        note.ContentMarkdown = request.ContentMarkdown;
        note.UpdatedAt = DateTime.UtcNow;

        await _context.SaveChangesAsync(cancellationToken);

        return Ok(new
        {
            note.Id,
            note.CourseId,
            CourseCode = note.Course?.Code ?? "GENERAL",
            CourseName = note.Course?.Name ?? "General Notes",
            note.Title,
            Content = note.ContentMarkdown,
            ContentMarkdown = note.ContentMarkdown,
            Tags = request.Tags ?? "#Notes",
            note.CreatedAt,
            note.UpdatedAt
        });
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteNote(Guid id, CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var note = await _context.NotebookPages
            .Include(page => page.Course)
            .SingleOrDefaultAsync(page => page.Id == id && page.Course != null && page.Course.UserId == userId.Value, cancellationToken);

        if (note is null) return NotFound(new { message = "Note not found." });

        _context.NotebookPages.Remove(note);
        await _context.SaveChangesAsync(cancellationToken);

        return NoContent();
    }

    private Guid? GetUserId() => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;
}
