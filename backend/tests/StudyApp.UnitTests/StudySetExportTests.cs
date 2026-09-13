using System.Text;
using StudyApp.Domain.Entities;
using StudyApp.Domain.Enums;
using Xunit;

namespace StudyApp.UnitTests;

public class StudySetExportTests
{
    [Fact]
    public void ExportStudySet_GeneratesMarkdownWithAllKeyComponents()
    {
        var course = new Course
        {
            Id = Guid.NewGuid(),
            Code = "BIO-101",
            Name = "General Biology",
            ColorHex = "#22C55E"
        };

        var studySet = new StudySet
        {
            Id = Guid.NewGuid(),
            CourseId = course.Id,
            Course = course,
            Title = "Cellular Respiration & Krebs Cycle",
            Description = "A detailed breakdown of glycolysis, the citric acid cycle, and oxidative phosphorylation.",
            CreatedAt = new DateTime(2026, 9, 12, 10, 0, 0, DateTimeKind.Utc)
        };

        // Add Source Document with OCR / Extracted text
        studySet.SourceDocuments.Add(new SourceDocument
        {
            Id = Guid.NewGuid(),
            StudySetId = studySet.Id,
            FileName = "lecture_whiteboard.png",
            FileType = "image/png",
            ExtractedText = "Visible on board: C6H12O6 + 6O2 -> 6CO2 + 6H2O + 36 ATP. Pyruvate decarboxylation yields Acetyl-CoA.",
            Status = DocumentStatus.Ready,
            CreatedAt = DateTime.UtcNow
        });

        // Add Practice Question
        var q1 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = studySet.Id,
            Type = QuestionType.MultipleChoice,
            Prompt = "Where does the Krebs Cycle occur in eukaryotic cells?",
            Explanation = "The Krebs cycle takes place in the mitochondrial matrix.",
            SortOrder = 1
        };
        q1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q1.Id, OptionText = "Mitochondrial Matrix", IsCorrect = true });
        q1.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q1.Id, OptionText = "Cytosol", IsCorrect = false, DistractorRationale = "Glycolysis occurs in cytosol." });
        studySet.Questions.Add(q1);

        // Add Identification Question
        var q2 = new Question
        {
            Id = Guid.NewGuid(),
            StudySetId = studySet.Id,
            Type = QuestionType.Identification,
            Prompt = "Name the molecule that enters the Krebs cycle after pyruvate oxidation.",
            Explanation = "Acetyl-CoA is the 2-carbon carrier that combines with oxaloacetate.",
            SortOrder = 2
        };
        q2.Options.Add(new QuestionOption { Id = Guid.NewGuid(), QuestionId = q2.Id, OptionText = "Acetyl-CoA", IsCorrect = true });
        studySet.Questions.Add(q2);

        // Build Markdown Export
        var sb = new StringBuilder();
        sb.AppendLine($"# Study Guide: {studySet.Title}");
        sb.AppendLine($"**Course:** {studySet.Course.Code} - {studySet.Course.Name}");
        sb.AppendLine($"**Generated:** {studySet.CreatedAt:yyyy-MM-dd HH:mm:ss UTC}");
        sb.AppendLine();
        sb.AppendLine("## Overview & Academic Summary");
        sb.AppendLine(studySet.Description);
        sb.AppendLine();

        sb.AppendLine("## Source Material & Extracted Text");
        foreach (var doc in studySet.SourceDocuments)
        {
            sb.AppendLine($"### Source: {doc.FileName} ({doc.FileType})");
            sb.AppendLine(doc.ExtractedText);
            sb.AppendLine();
        }

        sb.AppendLine("## Active Recall Practice Questions & Solutions");
        int qNum = 1;
        foreach (var q in studySet.Questions.OrderBy(x => x.SortOrder))
        {
            sb.AppendLine($"### Question {qNum++} [{q.Type}]");
            sb.AppendLine(q.Prompt);
            sb.AppendLine();

            if (q.Options.Any())
            {
                sb.AppendLine("**Options:**");
                char optChar = 'A';
                foreach (var opt in q.Options)
                {
                    var marker = opt.IsCorrect ? " [CORRECT]" : "";
                    sb.AppendLine($"- {optChar++}. {opt.OptionText}{marker}");
                }
                sb.AppendLine();
            }

            if (!string.IsNullOrWhiteSpace(q.Explanation))
            {
                sb.AppendLine($"**Explanation:** {q.Explanation}");
                sb.AppendLine();
            }
        }

        var exportOutput = sb.ToString();

        // Assertions
        Assert.Contains("# Study Guide: Cellular Respiration & Krebs Cycle", exportOutput);
        Assert.Contains("**Course:** BIO-101 - General Biology", exportOutput);
        Assert.Contains("## Source Material & Extracted Text", exportOutput);
        Assert.Contains("Visible on board: C6H12O6", exportOutput);
        Assert.Contains("Where does the Krebs Cycle occur", exportOutput);
        Assert.Contains("Mitochondrial Matrix [CORRECT]", exportOutput);
        Assert.Contains("Acetyl-CoA [CORRECT]", exportOutput);
    }
}
