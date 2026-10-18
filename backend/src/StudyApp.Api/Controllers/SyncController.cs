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

    private static DateTime NormalizeUtc(DateTime value)
    {
        if (value == default)
        {
            return DateTime.SpecifyKind(DateTime.UnixEpoch, DateTimeKind.Utc);
        }
        return value.Kind switch
        {
            DateTimeKind.Utc => value,
            DateTimeKind.Local => value.ToUniversalTime(),
            _ => DateTime.SpecifyKind(value, DateTimeKind.Utc)
        };
    }

    [HttpPost]
    public async Task<IActionResult> Sync([FromBody] SyncPushRequest? request)
    {
        var userIdClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
        {
            return Unauthorized();
        }

        request ??= new SyncPushRequest(
            DateTime.UtcNow.AddYears(-10),
            new List<SyncCourseDto>(),
            new List<SyncStudySetDto>(),
            new List<SyncQuestionDto>(),
            new List<SyncTestSessionDto>());

        var now = DateTime.UtcNow;
        var lastSyncedAtUtc = NormalizeUtc(request.LastSyncedAt);
        var courses = (request.Courses ?? new List<SyncCourseDto>())
            .Where(c => c.Id != Guid.Empty)
            .GroupBy(c => c.Id)
            .Select(g => g.Last())
            .ToList();
        var studySets = (request.StudySets ?? new List<SyncStudySetDto>())
            .Where(s => s.Id != Guid.Empty)
            .GroupBy(s => s.Id)
            .Select(g => g.Last())
            .ToList();
        var questions = (request.Questions ?? new List<SyncQuestionDto>())
            .Where(q => q.Id != Guid.Empty)
            .GroupBy(q => q.Id)
            .Select(g => g.Last())
            .ToList();
        var testSessions = (request.TestSessions ?? new List<SyncTestSessionDto>())
            .Where(ts => ts.Id != Guid.Empty)
            .GroupBy(ts => ts.Id)
            .Select(g => g.Last())
            .ToList();
        var acceptedCourseIds = new HashSet<Guid>();
        var acceptedStudySetIds = new HashSet<Guid>();

        // 1. Process incoming offline courses. Every update is constrained to the
        // authenticated owner; client generated IDs never grant access to a record.
        foreach (var c in courses)
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
            var clientUpdatedAt = NormalizeUtc(c.UpdatedAt);

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
                if (!c.IsDeleted && existing.UpdatedAt.HasValue && clientUpdatedAt <= NormalizeUtc(existing.UpdatedAt.Value))
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
        foreach (var s in studySets.Where(s => acceptedCourseIds.Contains(s.CourseId)))
        {
            if (string.IsNullOrWhiteSpace(s.Title) || s.Title.Trim().Length > 160 || s.Description?.Length > 10_000)
            {
                continue;
            }
            var studySetTitle = s.Title!.Trim();
            var studySetDescription = s.Description ?? string.Empty;
            var clientUpdatedAt = NormalizeUtc(s.UpdatedAt);

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
                acceptedStudySetIds.Add(s.Id);
            }
            else if (await _context.Courses.AnyAsync(c => c.Id == existing.CourseId && c.UserId == userId))
            {
                if (!s.IsDeleted && existing.UpdatedAt.HasValue && clientUpdatedAt <= NormalizeUtc(existing.UpdatedAt.Value))
                {
                    acceptedStudySetIds.Add(s.Id);
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
                acceptedStudySetIds.Add(s.Id);
            }
        }

        var persistedStudySetIds = await _context.StudySets
            .Where(s => s.Course != null && s.Course.UserId == userId)
            .Select(s => s.Id)
            .ToListAsync();
        acceptedStudySetIds.UnionWith(persistedStudySetIds);

        // 3. Process incoming offline Questions
        foreach (var q in questions)
        {
            if (!acceptedStudySetIds.Contains(q.StudySetId)) continue;
            var existing = await _context.Questions.FirstOrDefaultAsync(x => x.Id == q.Id);
            if (existing == null)
            {
                _context.Questions.Add(new Question
                {
                    Id = q.Id,
                    StudySetId = q.StudySetId,
                    Type = (QuestionType)q.Type,
                    Prompt = q.Prompt ?? string.Empty,
                    HintsJson = q.HintsJson ?? "[]",
                    Explanation = q.Explanation ?? string.Empty,
                    Difficulty = q.Difficulty,
                    SortOrder = q.SortOrder
                });
            }
            else if (acceptedStudySetIds.Contains(existing.StudySetId))
            {
                existing.Prompt = q.Prompt ?? existing.Prompt;
                existing.HintsJson = q.HintsJson ?? existing.HintsJson;
                existing.Explanation = q.Explanation ?? existing.Explanation;
                existing.Difficulty = q.Difficulty;
                existing.SortOrder = q.SortOrder;
            }
        }

        // 4. Process incoming offline TestSessions (Score records)
        foreach (var ts in testSessions)
        {
            if (!acceptedStudySetIds.Contains(ts.StudySetId)) continue;
            var completedAtUtc = NormalizeUtc(ts.CompletedAt);
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
                    CompletedAt = completedAtUtc
                });
            }
            else if (acceptedStudySetIds.Contains(existing.StudySetId))
            {
                existing.Score = ts.Score;
                existing.TotalQuestions = ts.TotalQuestions;
                existing.TimeSpentSeconds = ts.TimeSpentSeconds;
                existing.CompletedAt = completedAtUtc;
            }
        }

        // Update User last sync
        var user = await _context.Users.FindAsync(userId);
        if (user != null)
        {
            user.LastSyncAt = now;
        }

        try
        {
            await _context.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Ignore transient duplicate/FK race conditions during rapid multi-tab sync
        }

        // Gather updates on the server since client's LastSyncedAt
        var updatedCourses = await _context.Courses
            .AsNoTracking()
            .Where(c => c.UserId == userId && (c.UpdatedAt ?? c.CreatedAt) > lastSyncedAtUtc)
            .Select(c => new SyncCourseDto(c.Id, c.Code, c.Name, c.ColorHex, c.UpdatedAt ?? c.CreatedAt, false))
            .ToListAsync();

        var updatedStudySets = await _context.StudySets
            .AsNoTracking()
            .Where(s => s.Course != null && s.Course.UserId == userId && (s.UpdatedAt ?? s.CreatedAt) > lastSyncedAtUtc)
            .Select(s => new SyncStudySetDto(s.Id, s.CourseId, s.Title, s.Description, s.UpdatedAt ?? s.CreatedAt, false, s.Questions.Count))
            .ToListAsync();

        // Ensure parent courses of any updated study sets are always present so clients never orphan or discard them
        var existingCourseIds = updatedCourses.Select(c => c.Id).ToHashSet();
        var missingCourseIds = updatedStudySets.Select(s => s.CourseId).Where(cid => !existingCourseIds.Contains(cid)).Distinct().ToList();
        if (missingCourseIds.Count > 0)
        {
            var parentCourses = await _context.Courses
                .AsNoTracking()
                .Where(c => c.UserId == userId && missingCourseIds.Contains(c.Id))
                .Select(c => new SyncCourseDto(c.Id, c.Code, c.Name, c.ColorHex, c.UpdatedAt ?? c.CreatedAt, false))
                .ToListAsync();
            updatedCourses.AddRange(parentCourses);
        }

        var updatedQuestions = await _context.Questions
            .AsNoTracking()
            .Where(q => q.StudySet != null && q.StudySet.Course != null && q.StudySet.Course.UserId == userId
                     && (q.StudySet.UpdatedAt ?? q.StudySet.CreatedAt) > lastSyncedAtUtc)
            .Select(q => new SyncQuestionDto(q.Id, q.StudySetId, (int)q.Type, q.Prompt, q.HintsJson, q.Explanation, q.Difficulty, q.SortOrder))
            .ToListAsync();

        return Ok(new SyncPullResponse(now, updatedCourses, updatedStudySets, updatedQuestions));
    }
}
