import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { OpenAI } from 'openai';
import { VertexAI, SchemaType, HarmCategory, HarmBlockThreshold } from '@google-cloud/vertexai';
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

// Function to validate questions JSON structure
function validateQuestionsJSON(data: any): boolean {
  console.log('Validating questions structure');
  if (!data?.questions || !Array.isArray(data.questions)) {
    console.error('Missing questions array');
    return false;
  }
  return true;
}

// Function to validate question JSON structure
function validateQuestionJSON(q: any): boolean {
  const required = ['question', 'type', 'explanation', 'correctAnswer'];
  return required.every(field => q.hasOwnProperty(field));
}

// Define schema for structured output
const questionSchema = {
  type: SchemaType.OBJECT,
  properties: {
    questions: {
      type: SchemaType.ARRAY,
      items: {
        type: SchemaType.OBJECT,
        properties: {
          question: { type: SchemaType.STRING },
          type: { type: SchemaType.STRING },
          explanation: { type: SchemaType.STRING },
          correctAnswer: { type: SchemaType.STRING },
          topics: {
            type: SchemaType.ARRAY,
            items: { type: SchemaType.STRING }
          }
        },
        required: ["question", "type", "explanation", "correctAnswer"]
      }
    }
  }
};

// Export the generateQuestions function
export const generateQuestions = onDocumentWritten(
  {
    document: "requests/{requestId}",
    region: "asia-southeast1",//TODO try us-central1
    secrets: [OPENAI_API_KEY]
  },
  async (event) => {
    if (!event.data) return;
    
    const afterData = event.data.after;
    if (!afterData) return;
    
    const data = afterData.data() as RequestDoc;

    // Only process documents with 'pending' status
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
      console.log("Singapore Education Prompt:", singaporeEducationPrompt);
      
      // Model selection based on subject
      const needThinking = data.subject.toLowerCase().endsWith('mathematics');
      let responseContent;

      if (!needThinking) {
        // Initialize the generative model
        const model = vertexAI.preview.getGenerativeModel({
          model: 'gemini-2.0-flash',
          generationConfig: {
            temperature: 0.5,
            candidateCount: 1,
            maxOutputTokens: 2048
          },
          safetySettings: [
            {
              category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
              threshold: HarmBlockThreshold.BLOCK_NONE
            }
          ]
        });

        const result = await model.generateContent({
          contents: [{ role: 'user', parts: [{ text: singaporeEducationPrompt }] }],
          tools: [{
            functionDeclarations: [{
              name: 'questions',
              description: 'Generate exam questions',
              parameters: questionSchema
            }]
          }]
        });

        const response = await result.response;
        if (!response.candidates || response.candidates.length === 0) {
          throw new Error('No response generated from Vertex AI');
        }
        responseContent = response.candidates[0].content.parts[0].text;
      } else {
        // Thinking model - OpenAI O3
        const completion = await openai.chat.completions.create({
          model: 'o3-mini',
          messages: [{
            role: 'system',
            content: singaporeEducationPrompt
          }],
          response_format: { type: 'json_object' }
        });
        responseContent = completion?.choices?.[0]?.message?.content;
      }

      // Add null safety checks here
      if (!responseContent) {
        throw new Error('API returned empty response content');
      }

      // Parse response (works for both models)
      let responseJSON;
      try {
        responseJSON = JSON.parse(responseContent);
      } catch (error) {
        console.error('Failed to parse response:', responseContent);
        await afterData.ref.update({
          prompt: singaporeEducationPrompt,
          response: responseContent,
          modelName: !needThinking ? 'gemini-2.0-flash' : 'o3-mini',
          error: error instanceof Error ? error.message : 'Unknown error',
          status: "error",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        throw new Error('Invalid JSON response');
      }

      console.log("Raw OpenAI response:", JSON.stringify(responseJSON, null, 2));
      
      // Parse and validate the JSON response
      let parsedQuestions;
      try {
        parsedQuestions = responseJSON;
        console.log("Parsed questions:", JSON.stringify(parsedQuestions, null, 2));
        
        // Validate the structure
        if (!validateQuestionsJSON(parsedQuestions)) {
          console.error("Invalid structure:", parsedQuestions);
          throw new Error("Invalid response structure: missing questions array");
        }

        // Validate each question object
        parsedQuestions.questions.forEach((q: any, index: number) => {
          if (!validateQuestionJSON(q)) {
            console.error(`Invalid question ${index + 1}:`, q);
            throw new Error(`Question ${index + 1} is missing required fields`);
          }
        });

        // Update request document with prompt and response details
        await afterData.ref.update({
          prompt: singaporeEducationPrompt,
          response: responseContent,
          modelName: !needThinking ? 'gemini-2.0-flash' : 'o3-mini',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          status: "received",
          questionCount: parsedQuestions.questions.length
        });

      } catch (error: unknown) {
        console.error("JSON parsing error:", error);
        console.error("Response was:", responseContent);
        console.error("Response type:", typeof responseContent);
        console.error("Response length:", responseContent.length);
        console.error("First 100 chars:", responseContent.substring(0, 100));
        console.error("Last 100 chars:", responseContent.substring(responseContent.length - 100));

        await afterData.ref.update({
          prompt: singaporeEducationPrompt,
          response: responseContent,
          modelName: !needThinking ? 'gemini-2.0-flash' : 'o3-mini',
          error: error instanceof Error ? error.message : 'Unknown error',
          status: "error",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        const errorMessage = error instanceof Error ? error.message : 'Unknown error';
        throw new Error(`Invalid JSON response from OpenAI API: ${errorMessage}`);
      }

      console.log("Parsed questions length:", parsedQuestions.questions.length);
      // Create new questions documents for all the questions and save in questions collection
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
          topics: data.topic?.trim() ? [data.topic.trim().toLowerCase().replace(/[\s-]/g, '')] : [], //TODO : pick from pre-defined topics
          timestamp: admin.firestore.Timestamp.now()
        });
      });
      await Promise.all(promises);
      console.log("Created Questions");
      
      // Update the request document
      await afterData.ref.update({
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
  }
);
export * from './chat';
