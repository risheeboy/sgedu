import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { VertexAI } from "@google-cloud/vertexai";

admin.initializeApp();

// Initialize Vertex AI
const projectId = "edurishit"; // Replace with your project ID
const location = "asia-southeast1"; // Replace with your location
const vertexAI = new VertexAI({ project: projectId, location: location });
const model = "gemini-pro";

interface QuestionDoc {
  subject: string;
  grade: string;
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
      const generativeModel = vertexAI.preview.getGenerativeModel({
        model: model,
        generationConfig: {
          maxOutputTokens: 2048,
          temperature: 0.9,
          topP: 1,
        },
      });

      // Generate questions using Gemini
      const result = await generativeModel.generateContent({
        contents: [{ 
          role: "user", 
          parts: [{ 
            text: `You are a question generator. Generate 5 questions about ${data.subject} for ${data.grade} level students.
            Your response must be a valid JSON object with exactly this structure:
            {
              "questions": [
                {
                  "question": "string",
                  "correctAnswer": "string",
                  "explanation": "string",
                  "difficulty": "string",
                  "type": "string"
                }
              ]
            }
            Important: Return ONLY the JSON object, no other text or formatting.`
          }]
        }],
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
          if (!q.question || !q.correctAnswer || !q.explanation || !q.difficulty || !q.type) {
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
