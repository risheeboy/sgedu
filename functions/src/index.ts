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
  level: string;
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

      // Construct the prompt based on subject and level
      const prompt = `Generate 5 questions about ${data.subject} for ${
        data.level
      } level students. Format the response in the following JSON schema:
      {
        "questions": [
          {
            "question": "The question text",
            "correctAnswer": "The correct answer",
            "explanation": "Detailed explanation of the answer",
            "difficulty": "${data.level.toLowerCase()}",
            "type": "open-ended"
          }
        ]
      }`;

      // Generate questions using Gemini
      const result = await generativeModel.generateContent({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
      });
      const response = result.response;
      const generatedText = response.candidates?.[0]?.content?.parts?.[0]?.text;

      if (!generatedText) {
        throw new Error("No response generated from Gemini API");
      }

      // Update the document with generated questions
      await afterData.ref.update({
        questions: generatedText,
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
