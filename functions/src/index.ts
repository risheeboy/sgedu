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
  type: string;
  explanation: string;
  correctAnswer: string;
  topics: string[];
  mcqChoices?: string[];
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
      "correctAnswer": "string",
      "topics": ["string"],
      "mcqChoices": ["string"]
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
Return response in the following JSON structure (mcqChoices is required only for type MCQ):
{
  "questions": [
    {
      "question": "string",
      "type": "string (MCQ/Short Answer/Structured/Application)",
      "explanation": "string",
      "correctAnswer": "string",
      "topics": ["string"],
      "mcqChoices": ["string"]
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
        const requiredFields: (keyof Question)[] = ["question", "type", "explanation", "correctAnswer", "topics"];
        for (const field of requiredFields) {
          if (!q[field]) {
            throw new Error(`Question is missing required field: ${field}`);
          }
        }
        
        // Validate answer choices if present
        if (q.mcqChoices && (!Array.isArray(q.mcqChoices) || 
            !q.mcqChoices.every(choice => typeof choice === "string"))) {
          console.error("Invalid mcqChoices: must be an array of strings. Removing mcqChoices.");
          delete q.mcqChoices;
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
          topics: q.topics,
          mcqChoices: (q.mcqChoices || []),
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

// Listen for new score documents with pending status
export const validateAnswer = onDocumentWritten(
  {
    document: "games/{gameId}/scores/{scoreId}",
    region: "asia-southeast1"
  },
  async (event) => {
    // Make sure data exists
    if (!event.data || !event.data.after || !event.data.after.data()) {
      console.log('No data available');
      return null;
    }
    
    const scoreData = event.data.after.data() as {
      status: string;
      userAnswer: string;
      correctAnswer: string;
    };
    
    // Only process documents with pending status
    if (scoreData.status !== 'pending') {
      console.log('Score document is not pending, skipping validation');
      return null;
    }
    
    try {
      console.log(`Processing answer validation for score: ${event.params.scoreId}`);
      
      const userAnswer = scoreData.userAnswer;
      const correctAnswer = scoreData.correctAnswer;
      
      // Call Gemini model to analyze the answer
      const model = vertexAI.preview.getGenerativeModel({ model: 'gemini-2.0-pro-exp-02-05' });
      
      const prompt = `
        I need you to evaluate a student's answer to an educational question.
        
        Question's correct answer: "${correctAnswer}"
        Student's submitted answer: "${userAnswer}"
        Maximum score: 2
        
        Please analyze in detail and respond with a valid JSON object containing ONLY these fields:
        {
          "isCorrect": boolean, // true if the answer is correct, false otherwise
          "feedback": string, // constructive feedback explaining what was good, what was missing or incorrect
          "score": number // 0, 1 or 2 score to be assigned to the student's answer
        }
        
        Be somewhat lenient with minor spelling errors or different phrasings that convey the same meaning.
        Your feedback should be constructive, educational, and help the student improve.
      `;
      
      const result = await model.generateContent(prompt);
      
      // Check if there are candidates in the response
      if (!result.response || !result.response.candidates || 
          result.response.candidates.length === 0) {
        throw new Error('Gemini returned an empty response');
      }
      
      const candidate = result.response.candidates[0];
      if (!candidate.content || !candidate.content.parts || candidate.content.parts.length === 0) {
        throw new Error('Gemini returned an invalid content structure');
      }
      
      const textResponse = candidate.content.parts[0].text;
      if (!textResponse) {
        throw new Error('Gemini returned empty text content');
      }
      
      console.log('Generated feedback:', textResponse);
      
      // Extract JSON from the response
      let jsonMatch = textResponse.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        throw new Error('Could not extract valid JSON from model response');
      }
      
      const feedbackJson = JSON.parse(jsonMatch[0]) as {
        isCorrect: boolean;
        feedback: string;
        score: number;
      };
      
      // Make sure event.data.after exists
      if (!event.data || !event.data.after) {
        throw new Error('No document reference available');
      }
      
      // Update the score document with the results
      await event.data.after.ref.update({
        status: 'completed',
        isCorrect: feedbackJson.isCorrect,
        feedback: feedbackJson.feedback,
        score: feedbackJson.score,
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      return null;
    } catch (error) {
      console.error('Error validating answer:', error);
      
      // Make sure event.data.after exists
      if (!event.data || !event.data.after) {
        console.error('No document reference available for error update');
        return null;
      }
      
      // Update document with error status
      await event.data.after.ref.update({
        status: 'error',
        error: error instanceof Error ? error.message : 'Unknown error occurred',
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      return null;
    }
  }
);
export * from './chat';
