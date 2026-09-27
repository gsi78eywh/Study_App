using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using StudyApp.Application.Common.Interfaces;
using StudyApp.Domain.Common;

namespace StudyApp.Api.Controllers;

public record UpdateCourseGradeRequest(
    double? Units,
    double? TargetGrade,
    double? PrelimGrade,
    double? MidtermGrade,
    double? SemiFinalGrade,
    double? FinalGrade,
    double? PrelimWeight,
    double? MidtermWeight,
    double? SemiFinalWeight,
    double? FinalWeight
);

public record WhatIfGradeCalculatorRequest(
    double TargetGrade,
    double? PrelimGrade,
    double? MidtermGrade,
    double? SemiFinalGrade,
    double? PrelimWeight,
    double? MidtermWeight,
    double? SemiFinalWeight,
    double? FinalWeight
);

[ApiController]
[Route("api/v1/grades")]
[Authorize]
public sealed class GradesController : ControllerBase
{
    private readonly IApplicationDbContext _context;
    private readonly Microsoft.Extensions.Caching.Memory.IMemoryCache _cache;

    public GradesController(IApplicationDbContext context, Microsoft.Extensions.Caching.Memory.IMemoryCache cache)
    {
        _context = context;
        _cache = cache;
    }

    [HttpGet("summary")]
    public async Task<IActionResult> GetGradeSummary(CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var cacheKey = $"grades_summary_{userId.Value}";
        if (_cache.TryGetValue(cacheKey, out object? cached) && cached != null)
        {
            return Ok(cached);
        }

        var courses = await _context.Courses
            .Where(c => c.UserId == userId.Value)
            .OrderBy(c => c.Code)
            .ToListAsync(cancellationToken);

        double totalWeightedGwaPoints = 0.0;
        double totalUnitsForGwa = 0.0;
        double totalEnrolledUnits = 0.0;
        int highRiskCoursesCount = 0;

        var courseSummaries = new List<object>();

        foreach (var c in courses)
        {
            var (computedGrade, gwaPoint, status) = GwaCalculator.ComputeSubjectGrade(
                c.PrelimGrade,
                c.MidtermGrade,
                c.SemiFinalGrade,
                c.FinalGrade,
                c.PrelimWeight,
                c.MidtermWeight,
                c.SemiFinalWeight,
                c.FinalWeight
            );

            totalEnrolledUnits += c.Units;

            string riskLevel = "Low";
            if (computedGrade.HasValue)
            {
                if (computedGrade.Value < 75.0)
                {
                    riskLevel = "Critical";
                    highRiskCoursesCount++;
                }
                else if (computedGrade.Value < 78.0)
                {
                    riskLevel = "High";
                    highRiskCoursesCount++;
                }
                else if (computedGrade.Value < 82.0)
                {
                    riskLevel = "Medium";
                }
            }

            if (gwaPoint.HasValue && c.Units > 0)
            {
                totalWeightedGwaPoints += gwaPoint.Value * c.Units;
                totalUnitsForGwa += c.Units;
            }

            var whatIfFinal = GwaCalculator.CalculateNeededFinal(
                c.TargetGrade,
                c.PrelimGrade,
                c.MidtermGrade,
                c.SemiFinalGrade,
                c.PrelimWeight,
                c.MidtermWeight,
                c.SemiFinalWeight,
                c.FinalWeight
            );

            courseSummaries.Add(new
            {
                c.Id,
                c.Code,
                c.Name,
                c.ColorHex,
                c.Units,
                c.TargetGrade,
                c.PrelimGrade,
                c.MidtermGrade,
                c.SemiFinalGrade,
                c.FinalGrade,
                c.PrelimWeight,
                c.MidtermWeight,
                c.SemiFinalWeight,
                c.FinalWeight,
                c.GradingScale,
                ComputedGrade = computedGrade,
                GwaPoint = gwaPoint,
                Status = status,
                RiskLevel = riskLevel,
                WhatIf = whatIfFinal
            });
        }

        double? cumulativeGwa = totalUnitsForGwa > 0
            ? Math.Round(totalWeightedGwaPoints / totalUnitsForGwa, 3)
            : null;

        string overallHonorStatus = cumulativeGwa switch
        {
            null => "No Grades Recorded",
            <= 1.20 => "President's List Candidate (Highest Honors)",
            <= 1.45 => "Dean's List Candidate (First / Second Honors)",
            <= 1.75 => "Good Academic Standing",
            <= 2.50 => "Satisfactory Performance",
            <= 3.00 => "Passing Academic Threshold",
            _ => "Academic Probation / Risk (<75% Passing Threshold)"
        };

        var summaryResult = new
        {
            CumulativeGwa = cumulativeGwa,
            TotalEnrolledUnits = totalEnrolledUnits,
            TotalUnitsCalculated = totalUnitsForGwa,
            OverallHonorStatus = overallHonorStatus,
            HighRiskCoursesCount = highRiskCoursesCount,
            GradingScale = "USJ-R Standard Collegiate Scale",
            Courses = courseSummaries,
            ScaleTiers = GwaCalculator.UsjrScale
        };

        _cache.Set(cacheKey, summaryResult, TimeSpan.FromSeconds(30));

        return Ok(summaryResult);
    }

    [HttpPut("courses/{courseId:guid}")]
    public async Task<IActionResult> UpdateCourseGrades(
        Guid courseId,
        [FromBody] UpdateCourseGradeRequest request,
        CancellationToken cancellationToken)
    {
        var userId = GetUserId();
        if (userId is null) return Unauthorized();

        var course = await _context.Courses
            .FirstOrDefaultAsync(c => c.Id == courseId && c.UserId == userId.Value, cancellationToken);
        if (course is null) return NotFound(new { message = "Course not found." });

        if (request.Units.HasValue && request.Units.Value > 0) course.Units = request.Units.Value;
        if (request.TargetGrade.HasValue && request.TargetGrade.Value > 0) course.TargetGrade = request.TargetGrade.Value;

        if (request.PrelimGrade.HasValue) course.PrelimGrade = Math.Clamp(request.PrelimGrade.Value, 0.0, 100.0);
        if (request.MidtermGrade.HasValue) course.MidtermGrade = Math.Clamp(request.MidtermGrade.Value, 0.0, 100.0);
        if (request.SemiFinalGrade.HasValue) course.SemiFinalGrade = Math.Clamp(request.SemiFinalGrade.Value, 0.0, 100.0);
        if (request.FinalGrade.HasValue) course.FinalGrade = Math.Clamp(request.FinalGrade.Value, 0.0, 100.0);

        if (request.PrelimWeight.HasValue && request.PrelimWeight.Value > 0) course.PrelimWeight = request.PrelimWeight.Value;
        if (request.MidtermWeight.HasValue && request.MidtermWeight.Value > 0) course.MidtermWeight = request.MidtermWeight.Value;
        if (request.SemiFinalWeight.HasValue && request.SemiFinalWeight.Value > 0) course.SemiFinalWeight = request.SemiFinalWeight.Value;
        if (request.FinalWeight.HasValue && request.FinalWeight.Value > 0) course.FinalWeight = request.FinalWeight.Value;

        course.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync(cancellationToken);

        // Invalidate cached summary for this user
        _cache.Remove($"grades_summary_{userId.Value}");

        var (computedGrade, gwaPoint, status) = GwaCalculator.ComputeSubjectGrade(
            course.PrelimGrade,
            course.MidtermGrade,
            course.SemiFinalGrade,
            course.FinalGrade,
            course.PrelimWeight,
            course.MidtermWeight,
            course.SemiFinalWeight,
            course.FinalWeight
        );

        return Ok(new
        {
            success = true,
            course.Id,
            course.Code,
            course.Name,
            course.Units,
            course.TargetGrade,
            course.PrelimGrade,
            course.MidtermGrade,
            course.SemiFinalGrade,
            course.FinalGrade,
            course.PrelimWeight,
            course.MidtermWeight,
            course.SemiFinalWeight,
            course.FinalWeight,
            ComputedGrade = computedGrade,
            GwaPoint = gwaPoint,
            Status = status
        });
    }

    [HttpPost("calculator/what-if")]
    public IActionResult CalculateWhatIf([FromBody] WhatIfGradeCalculatorRequest request)
    {
        var result = GwaCalculator.CalculateNeededFinal(
            request.TargetGrade,
            request.PrelimGrade,
            request.MidtermGrade,
            request.SemiFinalGrade,
            request.PrelimWeight ?? 0.20,
            request.MidtermWeight ?? 0.20,
            request.SemiFinalWeight ?? 0.20,
            request.FinalWeight ?? 0.40
        );

        return Ok(result);
    }

    private Guid? GetUserId()
    {
        var idClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(idClaim, out var id) ? id : null;
    }
}
