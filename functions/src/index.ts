import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { VertexAI, type Tool, SchemaType } from "@google-cloud/vertexai";
import * as path from 'path';
import * as fs from 'fs/promises';

admin.initializeApp();

// Initialize Vertex AI
const projectId = "edurishit"; // Replace with your project ID
const location = "asia-southeast1"; // Replace with your location
const vertexAI = new VertexAI({ project: projectId, location: location });
const genAI = vertexAI.preview;

interface QuestionDoc {
  subject: string;
  syllabus: string;
  topic?: string;
  status: string;
  questions?: string;
  error?: string;
  timestamp: admin.firestore.Timestamp;
}

export const generateQuestions = onDocumentWritten(
  {
    document: "questions/{questionId}",
    region: "asia-southeast1"
  },
  async (event) => {
    if (!event.data) return;
    
    const afterData = event.data.after;
    if (!afterData) return;
    
    const data = afterData.data() as QuestionDoc;

    // Only process documents with 'pending' status
    if (data.status !== "pending") {
      return null;
    }

    try {
      // Get the generative model
      const model = genAI.getGenerativeModel({ model: "gemini-pro" });
      
      // Configure search tool for grounding
      const searchTool: Tool = {
        functionDeclarations: [{
          name: "googleSearch",
          description: "Search the web for relevant information",
          parameters: {
            type: SchemaType.OBJECT,
            properties: {}
          }
        }]
      };

      // Function to read syllabus markdown file
      const readSyllabusMarkdown = async (syllabus: string, subject: string): Promise<string> => {
        // Map full syllabus names to directory abbreviations
        const syllabusMap: { [key: string]: string } = {
          'Singapore GCE A-Level': 'SGCEA',
          'Singapore GCE O-Level': 'SGCEO'
        };

        const syllabusDir = syllabusMap[syllabus];
        if (!syllabusDir) {
          console.error(`Unknown syllabus: ${syllabus}`);
          return 'No specific syllabus details available.';
        }

        // Use relative path from the current file's directory
        const syllabusPath = path.join(__dirname, '../syllabus', syllabusDir, `${subject}.md`);
        
        try {
          const syllabusContent = await fs.readFile(syllabusPath, 'utf8');
          return syllabusContent;
        } catch (error) {
          console.error(`Could not read syllabus file for ${syllabus} ${subject}:`, error);
          return 'No specific syllabus details available.';
        }
      };

      // Read syllabus markdown content
      const syllabusMarkdown = await readSyllabusMarkdown(data.syllabus, data.subject);

      const singaporeEducationPrompt = `You are an expert education question paper setter, specializing in the Singapore education system. Use the search tool to find real past exam questions and educational resources, then generate 20 challenging questions about ${data.subject} for ${data.syllabus} ${data.topic ? `focusing on ${data.topic}` : ''} in Singapore.

Syllabus Details for Reference:
${syllabusMarkdown}

Before generating questions:
1. Search for past year ${data.subject} exam papers for ${data.syllabus} ${data.topic ? `in the ${data.topic} area` : ''} in Singapore
2. Search for ${data.subject} assessment objectives and marking rubrics for ${data.syllabus} ${data.topic ? `with focus on ${data.topic}` : ''}
3. Use these resources to ensure questions match national examination standards

Your response must be a valid JSON object with exactly this structure:
{
  "questions": [
    {
      "question": "string",
      "type": "string (MCQ/Short Answer/Structured/Application)",
      "explanation": "string",
      "correctAnswer": "string"
    }
  ]
}

Ensure questions:
- Focus on application and higher-order thinking skills
- Include real-world contexts and scenarios
- Use precise technical terminology from the syllabus
- Cover key examination topics and assessment objectives
- Follow official marking schemes and rubrics

Important: Return ONLY the JSON object, no other text or formatting.`;
      console.log("Singapore Education Prompt:", singaporeEducationPrompt);
      // Generate questions using Gemini
      const result = await model.generateContent({
        contents: [{ 
          role: "user", 
          parts: [{ 
            text: singaporeEducationPrompt
          }]
        }],
        tools: [searchTool],
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 8192,
        }
      });

      const response = result.response;
      console.log("Raw Gemini response:", JSON.stringify(response, null, 2));
      
      const generatedText = response.candidates?.[0]?.content?.parts?.[0]?.text;
      console.log("Generated text:", generatedText);

      if (!generatedText) {
        throw new Error("No response generated from Gemini API");
      }

      // Clean the response text to ensure it's valid JSON
      const cleanedText = generatedText
        .trim()
        .replace(/```json\n?|\n?```/g, '')
        .replace(/^[\s\n]*\{/, '{')  // Remove any whitespace/newlines before {
        .replace(/\}[\s\n]*$/, '}'); // Remove any whitespace/newlines after }
      
      console.log("Cleaned text:", cleanedText);
      
      // Parse and validate the JSON response
      let parsedQuestions;
      try {
        parsedQuestions = JSON.parse(cleanedText);
        console.log("Parsed questions:", JSON.stringify(parsedQuestions, null, 2));
        
        // Validate the structure
        if (!parsedQuestions.questions || !Array.isArray(parsedQuestions.questions)) {
          console.error("Invalid structure:", parsedQuestions);
          throw new Error("Invalid response structure: missing questions array");
        }

        // Validate each question object
        parsedQuestions.questions.forEach((q: any, index: number) => {
          if (!q.question || !q.correctAnswer || !q.explanation || !q.type) {
            console.error(`Invalid question ${index + 1}:`, q);
            throw new Error(`Question ${index + 1} is missing required fields`);
          }
        });

      } catch (error: unknown) {
        console.error("JSON parsing error:", error);
        console.error("Response was:", cleanedText);
        console.error("Response type:", typeof cleanedText);
        console.error("Response length:", cleanedText.length);
        console.error("First 100 chars:", cleanedText.substring(0, 100));
        console.error("Last 100 chars:", cleanedText.substring(cleanedText.length - 100));
        
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        throw new Error(`Invalid JSON response from Gemini API: ${errorMessage}`);
      }

      // Update the document with parsed questions
      await afterData.ref.update({
        questions: JSON.stringify(parsedQuestions),
        status: "completed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(), 
      });

      return null;
    } catch (error) {
      console.error("Error generating questions:", error);

      // Update document with error status
      await afterData.ref.update({
        status: "error",
        error: error instanceof Error ? error.message : "Unknown error occurred",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return null;
    }
  });
