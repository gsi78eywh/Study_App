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
    public async Task<IActionResult> GetNotes(
        [FromQuery] Guid? courseId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string? search = null,
        CancellationToken cancellationToken = default)
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

        if (!string.IsNullOrWhiteSpace(search))
        {
            var searchTrimmed = search.Trim();
            query = query.Where(n => n.Title.Contains(searchTrimmed) || n.ContentMarkdown.Contains(searchTrimmed));
        }

        var totalCount = await query.CountAsync(cancellationToken);
        var effectivePage = Math.Max(1, page);
        var effectivePageSize = Math.Clamp(pageSize, 1, 100);
        var totalPages = (int)Math.Ceiling(totalCount / (double)effectivePageSize);

        Response.Headers["X-Pagination-Total-Count"] = totalCount.ToString();
        Response.Headers["X-Pagination-Page"] = effectivePage.ToString();
        Response.Headers["X-Pagination-Page-Size"] = effectivePageSize.ToString();
        Response.Headers["X-Pagination-Total-Pages"] = totalPages.ToString();

        var notes = await query
            .OrderByDescending(n => n.UpdatedAt ?? n.CreatedAt)
            .Skip((effectivePage - 1) * effectivePageSize)
            .Take(effectivePageSize)
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

    [HttpGet("{id:guid}/export")]
    public async Task<IActionResult> ExportNote(Guid id, [FromQuery] string format = "markdown", CancellationToken cancellationToken = default)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var note = await _context.NotebookPages
            .Include(page => page.Course)
            .SingleOrDefaultAsync(page => page.Id == id && page.Course != null && page.Course.UserId == userId.Value, cancellationToken);

        if (note is null) return NotFound(new { message = "Note not found." });

        var courseName = note.Course?.Name ?? "General Notes";
        var courseCode = note.Course?.Code ?? "GENERAL";
        var cleanTitle = string.Join("_", note.Title.Split(Path.GetInvalidFileNameChars())).Replace(" ", "_");
        var fileName = $"{cleanTitle}.md";

        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"# {note.Title}");
        sb.AppendLine($"**Course:** {courseCode} - {courseName}");
        sb.AppendLine($"**Date:** {note.UpdatedAt ?? note.CreatedAt:yyyy-MM-dd HH:mm UTC}");
        sb.AppendLine();
        sb.AppendLine(note.ContentMarkdown);

        var content = sb.ToString();
        var acceptHeader = Request.Headers.Accept.ToString();
        if (acceptHeader.Contains("application/json") || format.Equals("json", StringComparison.OrdinalIgnoreCase))
        {
            return Ok(new
            {
                noteId = note.Id,
                title = note.Title,
                courseCode,
                courseName,
                fileName,
                content,
                format = "markdown"
            });
        }

        return File(System.Text.Encoding.UTF8.GetBytes(content), "text/markdown", fileName);
    }

    private Guid? GetUserId() => Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;
}
