import { onDocumentWritten } from "firebase-functions/v2/firestore";
//import { DocumentReference } from '@google-cloud/firestore';
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { OpenAI } from 'openai';

import * as path from 'path';
import * as fs from 'fs/promises';

admin.initializeApp();

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
// Define the RequestDoc interface
interface RequestDoc {
  subject: string;
  syllabus: string;
  topic?: string;
  status: string;
  error?: string;
  timestamp: admin.firestore.Timestamp;
}

/*
// Define the QuestionDoc interface
interface QuestionDoc {
  question: string;
  type: string;
  explanation: string;
  correctAnswer: string;
  subject: string;
  syllabus: string;
  request: DocumentReference;
  topics: string[];
  timestamp: admin.firestore.Timestamp;
}
*/

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

Important: Return ONLY the JSON object, no other text or formatting.`;
      console.log("Singapore Education Prompt:", singaporeEducationPrompt);
      // Generate questions using OpenAI
      const completion = await openai.chat.completions.create({
        model: 'o3-mini',
        messages: [{
          role: 'system',
          content: singaporeEducationPrompt
        }],
        response_format: { type: 'json_object' }
      });
      
      // Add null safety checks here
      const responseContent = completion?.choices?.[0]?.message?.content;
      if (!responseContent) {
        throw new Error("OpenAI API returned empty response content");
      }
      const responseJSON = JSON.parse(responseContent);
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

      } catch (error: unknown) {
        console.error("JSON parsing error:", error);
        console.error("Response was:", responseContent);
        console.error("Response type:", typeof responseContent);
        console.error("Response length:", responseContent.length);
        console.error("First 100 chars:", responseContent.substring(0, 100));
        console.error("Last 100 chars:", responseContent.substring(responseContent.length - 100));
        
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
          topics: [],// TODO: Generate topics
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
  });
