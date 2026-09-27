namespace StudyApp.Domain.Common;

public sealed record GwaScaleTier(string GwaPoint, double MinPercent, double MaxPercent, string Description, string StatusClass);

public sealed record WhatIfCalculationResult(
    double TargetPercentage,
    double CurrentWeightedEarned,
    double RemainingWeight,
    double NeededFinalScore,
    bool IsAttainable,
    double MaxPossibleGrade,
    double MinPossibleGrade,
    string StatusRecommendation
);

public static class GwaCalculator
{
    // Official University of San Jose-Recoletos (USJ-R) Standard Collegiate Grading Scale
    public static readonly IReadOnlyList<GwaScaleTier> UsjrScale = new List<GwaScaleTier>
    {
        new("1.0", 99.0, 100.0, "Excellent (Highest Academic Honors)", "honors"),
        new("1.1", 96.0, 98.99, "Superior Academic Standing", "honors"),
        new("1.2", 93.0, 95.99, "Dean's List First Honors Candidate", "honors"),
        new("1.3", 90.0, 92.99, "Dean's List Second Honors Candidate", "honors"),
        new("1.4", 87.0, 89.99, "High Average Performance", "good"),
        new("1.5", 84.0, 86.99, "Very Good Standing", "good"),
        new("1.6", 81.0, 83.99, "Above Average Performance", "good"),
        new("1.7", 78.0, 80.99, "Average Competency", "good"),
        new("2.0", 76.5, 77.99, "Fair Competency", "passing"),
        new("2.5", 75.5, 76.49, "Satisfactory Competency", "passing"),
        new("3.0", 75.0, 75.49, "Passing Threshold (75% Minimum Passing Mark)", "passing"),
        new("5.0", 0.0, 74.99, "Failure (Below 75.0% Minimum Passing Standard)", "danger")
    };

    public static double ConvertPercentToGwa(double percentage)
    {
        var clamped = Math.Clamp(percentage, 0.0, 100.0);
        foreach (var tier in UsjrScale)
        {
            if (clamped >= tier.MinPercent)
            {
                return double.Parse(tier.GwaPoint);
            }
        }
        return 5.0;
    }

    public static double ConvertGwaToApproxPercent(double gwa)
    {
        if (gwa <= 1.0) return 99.0;
        if (gwa <= 1.1) return 97.0;
        if (gwa <= 1.2) return 94.0;
        if (gwa <= 1.3) return 91.0;
        if (gwa <= 1.4) return 88.0;
        if (gwa <= 1.5) return 85.0;
        if (gwa <= 1.6) return 82.0;
        if (gwa <= 1.7) return 79.0;
        if (gwa <= 2.0) return 77.0;
        if (gwa <= 2.5) return 76.0;
        if (gwa <= 3.0) return 75.0;
        return 70.0;
    }

    public static (double? ComputedGrade, double? GwaPoint, string Status) ComputeSubjectGrade(
        double? prelim,
        double? midterm,
        double? semiFinal,
        double? final,
        double pw = 0.20,
        double mw = 0.20,
        double sw = 0.20,
        double fw = 0.40)
    {
        double totalEnteredWeight = 0.0;
        double weightedSum = 0.0;

        if (prelim.HasValue)
        {
            totalEnteredWeight += pw;
            weightedSum += prelim.Value * pw;
        }
        if (midterm.HasValue)
        {
            totalEnteredWeight += mw;
            weightedSum += midterm.Value * mw;
        }
        if (semiFinal.HasValue)
        {
            totalEnteredWeight += sw;
            weightedSum += semiFinal.Value * sw;
        }
        if (final.HasValue)
        {
            totalEnteredWeight += fw;
            weightedSum += final.Value * fw;
        }

        if (totalEnteredWeight <= 0.0)
        {
            return (null, null, "No Grades Entered");
        }

        // Current normalized running average
        var runningAverage = Math.Round(weightedSum / totalEnteredWeight, 2);
        var gwa = ConvertPercentToGwa(runningAverage);

        string status = runningAverage switch
        {
            >= 90.0 => "President's / Dean's List Pace",
            >= 84.0 => "Strong / Very Good",
            >= 78.0 => "In Good Standing",
            >= 75.0 => "Borderline Passing (Watch Risk)",
            _ => "Academic Risk / Failing Pace (<75%)"
        };

        return (runningAverage, gwa, status);
    }

    public static WhatIfCalculationResult CalculateNeededFinal(
        double targetGwaOrPercent,
        double? prelim,
        double? midterm,
        double? semiFinal,
        double pw = 0.20,
        double mw = 0.20,
        double sw = 0.20,
        double fw = 0.40)
    {
        // If target is in GWA point format (e.g. 1.0 - 5.0), convert to percent
        double targetPercent = targetGwaOrPercent <= 5.0
            ? ConvertGwaToApproxPercent(targetGwaOrPercent)
            : Math.Clamp(targetGwaOrPercent, 0.0, 100.0);

        double currentEarned = 0.0;
        if (prelim.HasValue) currentEarned += prelim.Value * pw;
        if (midterm.HasValue) currentEarned += midterm.Value * mw;
        if (semiFinal.HasValue) currentEarned += semiFinal.Value * sw;

        double finalWeight = fw > 0 ? fw : 0.40;
        double neededScore = Math.Round((targetPercent - currentEarned) / finalWeight, 1);

        double maxPossible = Math.Round(currentEarned + (100.0 * finalWeight), 1);
        double minPossible = Math.Round(currentEarned + (0.0 * finalWeight), 1);
        bool isAttainable = neededScore <= 100.0;

        string recommendation;
        if (neededScore > 100.0)
        {
            recommendation = $"Target unreachable with remaining final weight. Maximum possible grade is {maxPossible}% ({ConvertPercentToGwa(maxPossible)} GWA). Focus on securing a passing mark (needs {Math.Max(0, Math.Round((75.0 - currentEarned) / finalWeight, 1))}% on final).";
        }
        else if (neededScore <= 50.0)
        {
            recommendation = $"Safe buffer! You only need {Math.Max(0, neededScore)}% on your final exam to secure your target grade of {targetPercent}% ({ConvertPercentToGwa(targetPercent)} GWA).";
        }
        else if (neededScore <= 75.0)
        {
            recommendation = $"Achievable with regular study! Aim for at least {neededScore}% on your final exam.";
        }
        else
        {
            recommendation = $"High-stakes final exam! You need a score of {neededScore}% or higher. Prioritize high-yield retrieval sessions immediately.";
        }

        return new WhatIfCalculationResult(
            TargetPercentage: targetPercent,
            CurrentWeightedEarned: Math.Round(currentEarned, 2),
            RemainingWeight: finalWeight,
            NeededFinalScore: neededScore,
            IsAttainable: isAttainable,
            MaxPossibleGrade: maxPossible,
            MinPossibleGrade: minPossible,
            StatusRecommendation: recommendation
        );
    }
}
