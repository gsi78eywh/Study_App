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
        var courses = request.Courses ?? new List<SyncCourseDto>();
        var studySets = request.StudySets ?? new List<SyncStudySetDto>();
        var questions = request.Questions ?? new List<SyncQuestionDto>();
        var testSessions = request.TestSessions ?? new List<SyncTestSessionDto>();
        var acceptedCourseIds = new HashSet<Guid>();

        // 1. Process incoming offline courses. Every update is constrained to the
        // authenticated owner; client generated IDs never grant access to a record.
        foreach (var c in courses.Where(c => c.Id != Guid.Empty))
        {
            if (string.IsNullOrWhiteSpace(c.Code) || c.Code.Trim().Length > 32 ||
                string.IsNullOrWhiteSpace(c.Name) || c.Name.Trim().Length > 150 ||
                !System.Text.RegularExpressions.Regex.IsMatch(c.ColorHex ?? string.Empty, "^#[0-9A-Fa-f]{6}$"))
            {
                continue;
            }
            var courseCode = c.Code!.Trim();
            var courseName = c.Name!.Trim();
            var colorHex = c.ColorHex!.Trim().ToUpperInvariant();

            var existing = await _context.Courses.FirstOrDefaultAsync(x => x.Id == c.Id);
            if (existing == null)
            {
                if (c.IsDeleted) continue;
                _context.Courses.Add(new Course
                {
                    Id = c.Id,
                    UserId = userId,
                    Code = courseCode,
                    Name = courseName,
                    ColorHex = colorHex,
                    CreatedAt = now,
                    UpdatedAt = now
                });
                acceptedCourseIds.Add(c.Id);
            }
            else if (existing.UserId == userId)
            {
                // A stale cache cannot overwrite a change that the server has
                // already observed after the client's advertised version.
                if (!c.IsDeleted && existing.UpdatedAt.HasValue && c.UpdatedAt <= existing.UpdatedAt.Value)
                {
                    acceptedCourseIds.Add(c.Id);
                    continue;
                }
                if (c.IsDeleted)
                {
                    _context.Courses.Remove(existing);
                    continue;
                }
                existing.Code = courseCode;
                existing.Name = courseName;
                existing.ColorHex = colorHex;
                existing.UpdatedAt = now;
                acceptedCourseIds.Add(c.Id);
            }
        }

        var persistedCourseIds = await _context.Courses
            .Where(c => c.UserId == userId)
            .Select(c => c.Id)
            .ToListAsync();
        acceptedCourseIds.UnionWith(persistedCourseIds);

        // 2. Process incoming offline StudySets
        foreach (var s in studySets.Where(s => s.Id != Guid.Empty && acceptedCourseIds.Contains(s.CourseId)))
        {
            if (string.IsNullOrWhiteSpace(s.Title) || s.Title.Trim().Length > 160 || s.Description?.Length > 10_000)
            {
                continue;
            }
            var studySetTitle = s.Title!.Trim();
            var studySetDescription = s.Description ?? string.Empty;

            var existing = await _context.StudySets.FirstOrDefaultAsync(x => x.Id == s.Id);
            if (existing == null)
            {
                if (s.IsDeleted) continue;
                _context.StudySets.Add(new StudySet
                {
                    Id = s.Id,
                    CourseId = s.CourseId,
                    Title = studySetTitle,
                    Description = studySetDescription,
                    CreatedAt = now,
                    UpdatedAt = now
                });
            }
            else if (await _context.Courses.AnyAsync(c => c.Id == existing.CourseId && c.UserId == userId))
            {
                if (!s.IsDeleted && existing.UpdatedAt.HasValue && s.UpdatedAt <= existing.UpdatedAt.Value)
                {
                    continue;
                }
                if (s.IsDeleted)
                {
                    _context.StudySets.Remove(existing);
                    continue;
                }
                existing.Title = studySetTitle;
                existing.Description = studySetDescription;
                existing.UpdatedAt = now;
            }
        }

        // 3. Process incoming offline Questions
        foreach (var q in questions.Where(q => q.Id != Guid.Empty))
        {
            var ownsStudySet = await _context.StudySets.AnyAsync(s => s.Id == q.StudySetId && s.Course != null && s.Course.UserId == userId);
            if (!ownsStudySet && !studySets.Any(s => s.Id == q.StudySetId && acceptedCourseIds.Contains(s.CourseId) && !s.IsDeleted)) continue;
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
            else if (await _context.StudySets.AnyAsync(s => s.Id == existing.StudySetId && s.Course != null && s.Course.UserId == userId))
            {
                existing.Prompt = q.Prompt;
                existing.HintsJson = q.HintsJson;
                existing.Explanation = q.Explanation;
                existing.Difficulty = q.Difficulty;
                existing.SortOrder = q.SortOrder;
            }
        }

        // 4. Process incoming offline TestSessions (Score records)
        foreach (var ts in testSessions.Where(session => session.Id != Guid.Empty))
        {
            var ownsStudySet = await _context.StudySets.AnyAsync(s => s.Id == ts.StudySetId && s.Course != null && s.Course.UserId == userId);
            if (!ownsStudySet && !studySets.Any(s => s.Id == ts.StudySetId && acceptedCourseIds.Contains(s.CourseId) && !s.IsDeleted)) continue;
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
            else if (await _context.StudySets.AnyAsync(s => s.Id == existing.StudySetId && s.Course != null && s.Course.UserId == userId))
            {
                existing.Score = ts.Score;
                existing.TotalQuestions = ts.TotalQuestions;
                existing.TimeSpentSeconds = ts.TimeSpentSeconds;
                existing.CompletedAt = ts.CompletedAt;
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

        // Ensure parent courses of any updated study sets are always present so clients never orphan or discard them
        var existingCourseIds = updatedCourses.Select(c => c.Id).ToHashSet();
        var missingCourseIds = updatedStudySets.Select(s => s.CourseId).Where(cid => !existingCourseIds.Contains(cid)).Distinct().ToList();
        if (missingCourseIds.Count > 0)
        {
            var parentCourses = await _context.Courses
                .Where(c => c.UserId == userId && missingCourseIds.Contains(c.Id))
                .Select(c => new SyncCourseDto(c.Id, c.Code, c.Name, c.ColorHex, c.UpdatedAt ?? c.CreatedAt, false))
                .ToListAsync();
            updatedCourses.AddRange(parentCourses);
        }

        var updatedQuestions = await _context.Questions
            .Where(q => q.StudySet != null && q.StudySet.Course != null && q.StudySet.Course.UserId == userId
                     && (q.StudySet.UpdatedAt ?? q.StudySet.CreatedAt) > request.LastSyncedAt)
            .Select(q => new SyncQuestionDto(q.Id, q.StudySetId, (int)q.Type, q.Prompt, q.HintsJson, q.Explanation, q.Difficulty, q.SortOrder))
            .ToListAsync();

        return Ok(new SyncPullResponse(now, updatedCourses, updatedStudySets, updatedQuestions));
    }
}
