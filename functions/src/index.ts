import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { OpenAI } from 'openai';
import { VertexAI, HarmCategory, HarmBlockThreshold } from '@google-cloud/vertexai';
import * as path from 'path';
import * as fs from 'fs/promises';

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

// Initialize Firebase Admin
admin.initializeApp();

// Initialize Vertex AI
const vertexAI = new VertexAI({
  project: 'edurishit',
  location: 'us-central1'
}); 

// Define the RequestDoc interface
interface RequestDoc {
  subject: string;
  syllabus: string;
  topic?: string;
  status: string;
  error?: string;
  timestamp: admin.firestore.Timestamp;
}

// Define interfaces for type safety
interface Question {
  question: string;
  answerChoices?: string[];
  type: string;
  explanation: string;
  correctAnswer: string;
  topics?: string[];
}

interface QuestionResponse {
  questions: Question[];
}

// Export the generateQuestions function
export const generateQuestions = onDocumentWritten(
  {
    document: "requests/{requestId}",
    region: "asia-southeast1",
    secrets: [OPENAI_API_KEY]
  },
  async (event) => {
    if (!event.data) return;
    
    const afterData = event.data.after;
    if (!afterData) return;
    
    const data = afterData.data() as RequestDoc;

    if (data.status !== "pending") {
      return null;
    }

    try {
      const openaiApiKey = process.env.OPENAI_API_KEY || OPENAI_API_KEY.value();
      const openai = new OpenAI({
        apiKey: openaiApiKey
      });

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

      const singaporeEducationPrompt = `You are an expert education question paper setter, specializing in the Singapore education system. Use the search tool to find real past exam questions and educational resources, then generate 10 challenging questions about ${data.subject} for ${data.syllabus} ${data.topic ? `focusing on ${data.topic}` : ''} in Singapore.

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
- Dont preface the questions with "Question:" or similar prefixes such as "Short Answer:" or "MCQ:" or "Application:" or etc
- Include key concepts and application of the syllabus
- Include any relevant past exam questions or educational resources for context
- Include any commonly occuring questions or patterns in the syllabus and state them in the explanation
- Show any "trick" questions or any outstanding questions that have a high percentage of wrong answers in the past
- Follow the same structure as the example JSON provided

Important: Return ONLY the JSON object, no other text or formatting.`;
      
      // Build structured prompt for JSON output
      const jsonStructurePrompt = `
Return response in the following JSON structure:
{
  "questions": [
    {
      "question": "string",
      "answerChoices": ["string"],
      "type": "string",
      "explanation": "string",
      "correctAnswer": "string",
      "topics": ["string"]
    }
  ]
}

${singaporeEducationPrompt}`;

      let responseContent: string;
      if (!data.subject.toLowerCase().endsWith('mathematics')) {
        // Initialize the generative model
        const model = vertexAI.preview.getGenerativeModel({
          model: 'gemini-2.0-pro-exp-02-05',
          generationConfig: {
            temperature: 0.5,
            candidateCount: 1,
            maxOutputTokens:8192,
            responseMimeType: "application/json"
          },
          safetySettings: [
            {
              category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
              threshold: HarmBlockThreshold.BLOCK_NONE
            }
          ]
        });

        const result = await model.generateContent({
          contents: [{ role: 'user', parts: [{ text: jsonStructurePrompt }] }]
        });

        const response = await result.response;
        if (!response.candidates || response.candidates.length === 0) {
          throw new Error('No response generated from Vertex AI');
        }
        if (!response.candidates[0].content.parts[0].text) {
          throw new Error('Vertex AI returned empty response content');
        }
        responseContent = response.candidates[0].content.parts[0].text;
      } else {
        // Thinking model - OpenAI O3
        const completion = await openai.chat.completions.create({
          model: 'o3-mini',
          messages: [{
            role: 'system',
            content: jsonStructurePrompt
          }],
          response_format: { type: 'json_object' }
        });

        // Directly check nested properties
        if (!completion?.choices?.[0]?.message?.content) {
          throw new Error('OpenAI returned empty response content');
        }
        responseContent = completion.choices[0].message.content;
      }

      if (!responseContent) {
        throw new Error('API returned empty response content');
      }

      // Clean response content of any markdown formatting
      const cleanResponse = responseContent
      .replace(/^```json\s*/i, '')  // Remove opening ```json
      .replace(/\s*```\s*$/i, '')   // Remove closing ```
      .trim();

      // Always update the response content
      await afterData.ref.update({
        response: responseContent, // Keep original response for debugging
        cleanResponse: cleanResponse, // Store cleaned version
        modelName: !data.subject.toLowerCase().endsWith('mathematics') ? 'JSON Gemini 2.0 Experimental' : 'O3 Mini Thinking',
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

      // Parse and validate response
      const parsedQuestions = JSON.parse(cleanResponse) as QuestionResponse;
      
      // Validate required fields
      if (!Array.isArray(parsedQuestions.questions)) {
        throw new Error("Invalid response structure: questions must be an array");
      }

      for (const q of parsedQuestions.questions) {
        const requiredFields: (keyof Question)[] = ["question", "type", "explanation", "correctAnswer"];
        for (const field of requiredFields) {
          if (!q[field]) {
            throw new Error(`Question is missing required field: ${field}`);
          }
        }
        
        // Validate answer choices if present
        if (q.answerChoices && (!Array.isArray(q.answerChoices) || 
            !q.answerChoices.every(choice => typeof choice === "string"))) {
          throw new Error("Answer choices must be an array of strings");
        }
      }

      // Create questions in Firestore
      const promises = parsedQuestions.questions.map((q: any, index: number) => {
        console.log(`Creating question ${index + 1}: ${q.question}`);

        const questionDocRef = admin.firestore().collection('questions').doc();
        return questionDocRef.set({
          question: q.question,
          type: q.type,
          explanation: q.explanation,
          correctAnswer: q.correctAnswer,
          subject: data.subject,
          syllabus: data.syllabus,
          request: afterData.ref,
          topics: (q.topics || []),
          answerChoices: q.answerChoices || [],
          timestamp: admin.firestore.Timestamp.now()
        });
      });

      await Promise.all(promises);
      console.log("Created Questions");

      // Update final success status
      await afterData.ref.update({
        status: "completed",
        questionCount: parsedQuestions.questions.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });

    } catch (error) {
      console.error("Error processing response:", error);
      // Update error status but preserve the prompt and response
      await afterData.ref.update({
        status: "error",
        error: error instanceof Error ? error.message : "Unknown error occurred",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    return null;
  }
);
export * from './chat';
