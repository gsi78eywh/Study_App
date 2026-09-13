using StudyApp.Infrastructure.AiServices;
using Xunit;

namespace StudyApp.UnitTests;

public class NoteScriptParserTests
{
    [Fact]
    public void NoteScriptParser_ExtractsAllMultipleChoiceQuestionsWithDistinctChoices()
    {
        var script = """
        Cell Biology Exam Review Notes

        1. What is the powerhouse of the cell?
        A. Nucleus
        B. Mitochondria
        C. Ribosome
        D. Chloroplast
        Answer: B

        2. What is the process by which green plants manufacture glucose?
        a. Fermentation
        b. Glycolysis
        c. Photosynthesis
        d. Cellular Respiration
        Answer: c

        3. Which cellular organelle contains genetic DNA material?
        (A) Endoplasmic Reticulum
        (B) Nucleus
        (C) Golgi Complex
        (D) Lysosome
        Ans: B
        """;

        var result = NoteScriptSynthesizer.SynthesizeFromNotes("Biology 101", script);

        Assert.NotNull(result);
        Assert.True(result.Questions.Count >= 3, $"Expected at least 3 questions, got {result.Questions.Count}");

        // Check Question 1
        var q1 = result.Questions[0];
        Assert.Contains("powerhouse of the cell", q1.Prompt, StringComparison.OrdinalIgnoreCase);
        Assert.Equal("Mitochondria", q1.CorrectAnswer);
        Assert.NotNull(q1.Options);
        Assert.Equal(4, q1.Options!.Count);
        Assert.Single(q1.Options, o => o.IsCorrect);
        Assert.Equal("Mitochondria", q1.Options.First(o => o.IsCorrect).Text);

        // Verify all 4 options are distinct
        var q1Texts = q1.Options.Select(o => o.Text).Distinct().ToList();
        Assert.Equal(4, q1Texts.Count);

        // Check Question 2
        var q2 = result.Questions[1];
        Assert.Contains("green plants manufacture glucose", q2.Prompt, StringComparison.OrdinalIgnoreCase);
        Assert.Equal("Photosynthesis", q2.CorrectAnswer);
        Assert.NotNull(q2.Options);
        Assert.Equal(4, q2.Options!.Count);
        Assert.Single(q2.Options, o => o.IsCorrect);
        Assert.Equal("Photosynthesis", q2.Options.First(o => o.IsCorrect).Text);

        // Check Question 3
        var q3 = result.Questions[2];
        Assert.Contains("genetic DNA material", q3.Prompt, StringComparison.OrdinalIgnoreCase);
        Assert.Equal("Nucleus", q3.CorrectAnswer);
        Assert.NotNull(q3.Options);
        Assert.Equal(4, q3.Options!.Count);
        Assert.Single(q3.Options, o => o.IsCorrect);
        Assert.Equal("Nucleus", q3.Options.First(o => o.IsCorrect).Text);

        // None of the questions should have repeated dummy answers
        foreach (var q in result.Questions)
        {
            Assert.DoesNotContain("Applying primary verified principles", q.CorrectAnswer);
            Assert.NotNull(q.Options);
            Assert.All(q.Options!, opt => Assert.DoesNotContain("Applying primary verified principles", opt.Text));
        }
    }

    [Fact]
    public void NoteScriptParser_ExtractsQAPairsAndConvertsToMcqWithFourDistinctOptions()
    {
        var script = """
        Physics 201 Practice Q&A:
        Q: What is Newton's First Law of Motion?
        A: An object at rest stays at rest unless acted upon by a net external force.

        Question: What is the unit of electrical resistance?
        Answer: Ohm

        Q3: What physical quantity is measured in Joules?
        Ans: Energy
        """;

        var result = NoteScriptSynthesizer.SynthesizeFromNotes("Physics 201", script);

        Assert.NotNull(result);
        Assert.True(result.Questions.Count >= 3);

        foreach (var q in result.Questions)
        {
            if (q.Type == "multiple_choice")
            {
                Assert.NotNull(q.Options);
                Assert.Equal(4, q.Options!.Count);
                Assert.Single(q.Options, o => o.IsCorrect);
                // Distractors must not duplicate each other
                var uniqueOptions = q.Options.Select(o => o.Text.Trim().ToLowerInvariant()).Distinct().ToList();
                Assert.Equal(4, uniqueOptions.Count);
            }
        }
    }

    [Fact]
    public void NoteScriptParser_ExtractsDefinitionsWithoutDuplicatingAnswers()
    {
        var script = """
        Anatomy & Physiology Terms:
        - Osmosis: The movement of water across a semipermeable membrane from low to high solute concentration.
        - Homeostasis: The maintenance of a stable internal environment despite external fluctuations.
        - Metabolism: The sum of all chemical reactions that occur within a living organism.
        - Enzyme: A biological catalyst that speeds up chemical reactions without being consumed.
        """;

        var result = NoteScriptSynthesizer.SynthesizeFromNotes("Anatomy", script);

        Assert.NotNull(result);
        Assert.True(result.Questions.Count >= 4);

        // Verify every multiple choice question has 4 distinct options and only 1 correct option
        foreach (var q in result.Questions.Where(q => q.Type == "multiple_choice"))
        {
            Assert.NotNull(q.Options);
            Assert.Equal(4, q.Options!.Count);
            Assert.Single(q.Options, o => o.IsCorrect);
            var uniqueOptionTexts = q.Options.Select(o => o.Text.Trim().ToLowerInvariant()).Distinct().ToList();
            Assert.Equal(4, uniqueOptionTexts.Count);
        }

        // Verify correct answers are not all the same text
        var distinctCorrectAnswers = result.Questions.Select(q => q.CorrectAnswer).Distinct().ToList();
        Assert.True(distinctCorrectAnswers.Count > 1, "Questions must have distinct correct answers based on notes.");
    }

    [Fact]
    public void NoteScriptParser_RetainsExactNotesInExtractedText()
    {
        var rawNotes = "Chapter 3 Lecture Notes: Enzymes act as biological catalysts. Substrates bind to the active site.";
        var result = NoteScriptSynthesizer.SynthesizeFromNotes("Biochemistry", rawNotes);

        Assert.Equal(rawNotes, result.ExtractedText);
        Assert.NotEmpty(result.HighYieldBulletPoints);
        Assert.NotEmpty(result.Summary);
    }

    [Fact]
    public void NoteScriptParser_ExtractsUserQuestionnaireAccurately()
    {
        var script = """
        Question 1: What is Machine Learning?

        A) A set of rigid rules hard-coded by programmers to solve specific tasks

        B) A subset of AI where systems learn from data and improve without being explicitly programmed

        C) A physical hardware component used to accelerate computer processing speeds

        D) A robotic method for assembling mechanical components in factories
        Answer: B

        Question 2: What does the term "Generative AI" refer to?

        A) AI designed specifically to destroy or overwrite old files

        B) AI that creates new, original content such as text, images, or audio based on patterns

        C) AI that is strictly limited to classifying and categorizing existing datasets

        D) AI used exclusively to clean and organize relational databases
        Answer: B

        Question 3: In the context of AI, what is a "hallucination"?

        A) When an AI system's hardware overheats and shuts down unexpectedly

        B) When a model generates factually incorrect or nonsensical outputs but presents them confidently as facts

        C) A built-in feature that allows AI to dream and create abstract art

        D) A process for filtering out corrupted files in training datasets
        Answer: B

        Question 4: What is a Large Language Model (LLM)?

        A) A model designed exclusively to generate high-resolution video content

        B) A neural network trained on massive amounts of text to understand and generate human language

        C) A specialized relational database optimized for storing multiple human languages

        D) A traditional programming language used to build operating systems
        Answer: B

        Question 5: What does NLP stand for in Artificial Intelligence?

        A) Natural Learning Process

        B) Neural Logic Programming

        C) Natural Language Processing

        D) Network Layer Protocol
        Answer: C

        Question 6: What is the primary purpose of the Turing Test?

        A) To measure the mathematical processing speed of a supercomputer

        B) To evaluate if a machine can exhibit intelligent behavior indistinguishable from a human

        C) To test the maximum memory capacity of a new AI model

        D) To automatically debug code in a machine learning algorithm
        Answer: B

        Question 7: What are the two main components of a Generative Adversarial Network (GAN)?

        A) An Encoder and a Decoder

        B) A Generator and a Discriminator

        C) A Scanner and a Printer

        D) A Teacher model and a Student model
        Answer: B

        Question 8: Which term describes the fundamental building blocks of an Artificial Neural Network?

        A) Spreadsheets

        B) Central Processing Units (CPUs)

        C) Nodes (or Neurons)

        D) Compilers
        Answer: C

        Question 9: What does "Overfitting" mean in machine learning?

        A) When a model is too simple to capture the underlying patterns in the training data

        B) When a model learns the training data too well, including its noise, causing it to perform poorly on new data

        C) When a dataset contains too many variables for a computer to process

        D) When a developer writes too much code for a simple algorithmic task
        Answer: B

        Question 10: Why is algorithmic bias a significant concern in AI systems?

        A) It significantly slows down the processing speed of AI hardware

        B) It can lead to unfair, skewed, or discriminatory outcomes based on flawed historical training data

        C) It completely prevents an AI model from generating any output when prompted

        D) It causes the system to randomly delete user inputs
        Answer: B for  example this test questinnares i will put all i want is to create a multipl;e  choice on tthe app and theres a selection of correct answers it must be correct realable and accurate
        """;

        var result = NoteScriptSynthesizer.SynthesizeFromNotes("AI Questionnaire", script);

        Assert.NotNull(result);
        Assert.Equal(10, result.Questions.Count);

        // Verify Question 1
        var q1 = result.Questions[0];
        Assert.Contains("Machine Learning", q1.Prompt);
        Assert.Equal("A subset of AI where systems learn from data and improve without being explicitly programmed", q1.CorrectAnswer);
        Assert.Equal(4, q1.Options!.Count);
        Assert.Single(q1.Options, o => o.IsCorrect);
        Assert.Equal("A subset of AI where systems learn from data and improve without being explicitly programmed", q1.Options.First(o => o.IsCorrect).Text);

        // Verify Question 5 (Answer C)
        var q5 = result.Questions[4];
        Assert.Contains("NLP", q5.Prompt);
        Assert.Equal("Natural Language Processing", q5.CorrectAnswer);
        Assert.Equal("Natural Language Processing", q5.Options!.First(o => o.IsCorrect).Text);

        // Verify Question 8 (Answer C)
        var q8 = result.Questions[7];
        Assert.Contains("Artificial Neural Network", q8.Prompt);
        Assert.Equal("Nodes (or Neurons)", q8.CorrectAnswer);
        Assert.Equal("Nodes (or Neurons)", q8.Options!.First(o => o.IsCorrect).Text);

        // Verify Question 10 with trailing text in answer line (Answer B)
        var q10 = result.Questions[9];
        Assert.Contains("algorithmic bias", q10.Prompt);
        Assert.Equal("It can lead to unfair, skewed, or discriminatory outcomes based on flawed historical training data", q10.CorrectAnswer);
        Assert.Equal("It can lead to unfair, skewed, or discriminatory outcomes based on flawed historical training data", q10.Options!.First(o => o.IsCorrect).Text);

        // Verify all 10 questions have 4 distinct options and exactly 1 correct answer
        for (int i = 0; i < result.Questions.Count; i++)
        {
            var q = result.Questions[i];
            Assert.Equal("multiple_choice", q.Type);
            Assert.NotNull(q.Options);
            Assert.Equal(4, q.Options!.Count);
            Assert.Single(q.Options, o => o.IsCorrect);
            var distinctTexts = q.Options.Select(o => o.Text.Trim().ToLowerInvariant()).Distinct().ToList();
            Assert.Equal(4, distinctTexts.Count);
        }
    }

    [Fact]
    public void NoteScriptParser_ExtractsMarkdownFormattedUserQuestionnaireAccurately()
    {
        var script = """
        **Question 1: What is Machine Learning?**

        * A) A set of rigid rules hard-coded by programmers to solve specific tasks
        * B) A subset of AI where systems learn from data and improve without being explicitly programmed
        * C) A physical hardware component used to accelerate computer processing speeds
        * D) A robotic method for assembling mechanical components in factories
        **Answer:** B

        **Question 2: What does the term "Generative AI" refer to?**

        * A) AI designed specifically to destroy or overwrite old files
        * B) AI that creates new, original content such as text, images, or audio based on patterns
        * C) AI that is strictly limited to classifying and categorizing existing datasets
        * D) AI used exclusively to clean and organize relational databases
        **Answer:** B

        **Question 3: In the context of AI, what is a "hallucination"?**

        * A) When an AI system's hardware overheats and shuts down unexpectedly
        * B) When a model generates factually incorrect or nonsensical outputs but presents them confidently as facts
        * C) A built-in feature that allows AI to dream and create abstract art
        * D) A process for filtering out corrupted files in training datasets
        **Answer:** B

        **Question 4: What is a Large Language Model (LLM)?**

        * A) A model designed exclusively to generate high-resolution video content
        * B) A neural network trained on massive amounts of text to understand and generate human language
        * C) A specialized relational database optimized for storing multiple human languages
        * D) A traditional programming language used to build operating systems
        **Answer:** B

        **Question 5: What does NLP stand for in Artificial Intelligence?**

        * A) Natural Learning Process
        * B) Neural Logic Programming
        * C) Natural Language Processing
        * D) Network Layer Protocol
        **Answer:** C

        **Question 6: What is the primary purpose of the Turing Test?**

        * A) To measure the mathematical processing speed of a supercomputer
        * B) To evaluate if a machine can exhibit intelligent behavior indistinguishable from a human
        * C) To test the maximum memory capacity of a new AI model
        * D) To automatically debug code in a machine learning algorithm
        **Answer:** B

        **Question 7: What are the two main components of a Generative Adversarial Network (GAN)?**

        * A) An Encoder and a Decoder
        * B) A Generator and a Discriminator
        * C) A Scanner and a Printer
        * D) A Teacher model and a Student model
        **Answer:** B

        **Question 8: Which term describes the fundamental building blocks of an Artificial Neural Network?**

        * A) Spreadsheets
        * B) Central Processing Units (CPUs)
        * C) Nodes (or Neurons)
        * D) Compilers
        **Answer:** C

        **Question 9: What does "Overfitting" mean in machine learning?**

        * A) When a model is too simple to capture the underlying patterns in the training data
        * B) When a model learns the training data too well, including its noise, causing it to perform poorly on new data
        * C) When a dataset contains too many variables for a computer to process
        * D) When a developer writes too much code for a simple algorithmic task
        **Answer:** B

        **Question 10: Why is algorithmic bias a significant concern in AI systems?**

        * A) It significantly slows down the processing speed of AI hardware
        * B) It can lead to unfair, skewed, or discriminatory outcomes based on flawed historical training data
        * C) It completely prevents an AI model from generating any output when prompted
        * D) It causes the system to randomly delete user inputs
        **Answer:** B so it is too far so what is the purpose of this app if it doenst release accurate results?
        """;

        var result = NoteScriptSynthesizer.SynthesizeFromNotes("AI Questionnaire", script);

        Assert.NotNull(result);
        Assert.Equal(10, result.Questions.Count);

        // Verify Question 1
        var q1 = result.Questions[0];
        Assert.Equal("What is Machine Learning?", q1.Prompt);
        Assert.Equal("A subset of AI where systems learn from data and improve without being explicitly programmed", q1.CorrectAnswer);
        Assert.Equal(4, q1.Options!.Count);
        Assert.Single(q1.Options, o => o.IsCorrect);
        Assert.Equal("A subset of AI where systems learn from data and improve without being explicitly programmed", q1.Options.First(o => o.IsCorrect).Text);

        // Verify Question 5 (Answer C)
        var q5 = result.Questions[4];
        Assert.Equal("What does NLP stand for in Artificial Intelligence?", q5.Prompt);
        Assert.Equal("Natural Language Processing", q5.CorrectAnswer);
        Assert.Equal("Natural Language Processing", q5.Options!.First(o => o.IsCorrect).Text);

        // Verify Question 8 (Answer C)
        var q8 = result.Questions[7];
        Assert.Equal("Which term describes the fundamental building blocks of an Artificial Neural Network?", q8.Prompt);
        Assert.Equal("Nodes (or Neurons)", q8.CorrectAnswer);
        Assert.Equal("Nodes (or Neurons)", q8.Options!.First(o => o.IsCorrect).Text);

        // Verify Question 10 (Answer B)
        var q10 = result.Questions[9];
        Assert.Equal("Why is algorithmic bias a significant concern in AI systems?", q10.Prompt);
        Assert.Equal("It can lead to unfair, skewed, or discriminatory outcomes based on flawed historical training data", q10.CorrectAnswer);
        Assert.Equal("It can lead to unfair, skewed, or discriminatory outcomes based on flawed historical training data", q10.Options!.First(o => o.IsCorrect).Text);

        // Check that none of the questions are "Fill in the blank"
        Assert.DoesNotContain(result.Questions, q => q.Prompt.StartsWith("Fill in the blank", StringComparison.OrdinalIgnoreCase));

        // Check that none of the options contain "Parameter"
        foreach (var q in result.Questions)
        {
            Assert.NotNull(q.Options);
            Assert.DoesNotContain(q.Options!, o => o.Text.Contains("Parameter", StringComparison.OrdinalIgnoreCase));
        }
    }
}
