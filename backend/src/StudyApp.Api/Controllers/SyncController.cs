using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Application.DTOs.Sync;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;

namespace StudyApp.Api.Controllers;

[ApiController]
[Route("api/v1/sync")]
[Authorize]
public class SyncController : ControllerBase
{
    private readonly IApplicationDbContext _context;

    public SyncController(IApplicationDbContext context)
    {
        _context = context;
    }

    [HttpPost]
    public async Task<IActionResult> Sync([FromBody] SyncPushRequest request)
    {
        var userIdClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
        {
            return Unauthorized();
        }

        var now = DateTime.UtcNow;

        // 1. Process incoming offline Courses (safely handle existing IDs)
        foreach (var c in request.Courses)
        {
            var existing = await _context.Courses.FirstOrDefaultAsync(x => x.Id == c.Id);
            if (existing == null)
            {
                _context.Courses.Add(new Course
                {
                    Id = c.Id,
                    UserId = userId,
                    Code = c.Code,
                    Name = c.Name,
                    ColorHex = c.ColorHex,
                    CreatedAt = now,
                    UpdatedAt = c.UpdatedAt
                });
            }
            else if (existing.UserId == userId)
            {
                existing.Code = c.Code;
                existing.Name = c.Name;
                existing.ColorHex = c.ColorHex;
                existing.UpdatedAt = c.UpdatedAt;
            }
        }

        // 2. Process incoming offline StudySets
        foreach (var s in request.StudySets)
        {
            var existing = await _context.StudySets.FirstOrDefaultAsync(x => x.Id == s.Id);
            if (existing == null)
            {
                _context.StudySets.Add(new StudySet
                {
                    Id = s.Id,
                    CourseId = s.CourseId,
                    Title = s.Title,
                    Description = s.Description,
                    CreatedAt = now,
                    UpdatedAt = s.UpdatedAt
                });
            }
            else
            {
                existing.Title = s.Title;
                existing.Description = s.Description;
                existing.UpdatedAt = s.UpdatedAt;
            }
        }

        // 3. Process incoming offline Questions
        foreach (var q in request.Questions)
        {
            var existing = await _context.Questions.FirstOrDefaultAsync(x => x.Id == q.Id);
            if (existing == null)
            {
                _context.Questions.Add(new Question
                {
                    Id = q.Id,
                    StudySetId = q.StudySetId,
                    Type = (QuestionType)q.Type,
                    Prompt = q.Prompt,
                    HintsJson = q.HintsJson,
                    Explanation = q.Explanation,
                    Difficulty = q.Difficulty,
                    SortOrder = q.SortOrder
                });
            }
        }

        // 4. Process incoming offline TestSessions (Score records)
        foreach (var ts in request.TestSessions)
        {
            var existing = await _context.TestSessions.FirstOrDefaultAsync(x => x.Id == ts.Id);
            if (existing == null)
            {
                _context.TestSessions.Add(new TestSession
                {
                    Id = ts.Id,
                    StudySetId = ts.StudySetId,
                    Mode = (StudyMode)ts.Mode,
                    Score = ts.Score,
                    TotalQuestions = ts.TotalQuestions,
                    TimeSpentSeconds = ts.TimeSpentSeconds,
                    CompletedAt = ts.CompletedAt
                });
            }
        }

        // Update User last sync
        var user = await _context.Users.FindAsync(userId);
        if (user != null)
        {
            user.LastSyncAt = now;
        }

        await _context.SaveChangesAsync();

        // 5. Gather updates on the server since client's LastSyncedAt
        var updatedCourses = await _context.Courses
            .Where(c => c.UserId == userId && (c.UpdatedAt ?? c.CreatedAt) > request.LastSyncedAt)
            .Select(c => new SyncCourseDto(c.Id, c.Code, c.Name, c.ColorHex, c.UpdatedAt ?? c.CreatedAt, false))
            .ToListAsync();

        var updatedStudySets = await _context.StudySets
            .Where(s => s.Course != null && s.Course.UserId == userId && (s.UpdatedAt ?? s.CreatedAt) > request.LastSyncedAt)
            .Select(s => new SyncStudySetDto(s.Id, s.CourseId, s.Title, s.Description, s.UpdatedAt ?? s.CreatedAt, false, s.Questions.Count))
            .ToListAsync();

        var updatedQuestions = await _context.Questions
            .Where(q => q.StudySet != null && q.StudySet.Course != null && q.StudySet.Course.UserId == userId)
            .Select(q => new SyncQuestionDto(q.Id, q.StudySetId, (int)q.Type, q.Prompt, q.HintsJson, q.Explanation, q.Difficulty, q.SortOrder))
            .ToListAsync();

        return Ok(new SyncPullResponse(now, updatedCourses, updatedStudySets, updatedQuestions));
    }
}
