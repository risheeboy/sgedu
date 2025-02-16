import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { VertexAI } from '@google-cloud/vertexai';
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as admin from 'firebase-admin';

const vertexAI = new VertexAI({
  project: 'edurishit',
  location: 'asia-southeast1',
});

const generativeModel = vertexAI.preview.getGenerativeModel({
  model: 'gemini-pro',
});

export const handleChatMessage = onDocumentWritten(
  {
    document: "chat_sessions/{sessionId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const after = event.data?.after.data();
    if (!after) return;

    const messages = after.messages;
    if (!messages) {
      console.log("No messages in document");
      return;
    }

    for (const message of messages) {
      if (message && message.isUser !== undefined) {
        console.log(`Message is from user: ${message.isUser}`);
      } else {
        console.log("Message is missing 'isUser' property");
      }
    }

    const latestMessage = messages[messages.length - 1];

    if (!latestMessage || (latestMessage && latestMessage.isUser === undefined) || !latestMessage.isUser) return null;

    const prompt = `Context:
    Question: ${after.context.question}
    Answer: ${after.context.answer}
    Explanation: ${after.context.explanation}

    Student Query: ${latestMessage.content}

    Please provide a helpful response to the student's query
    based on the question context above.`;

    const resp = await generativeModel.generateContent({
      contents: [{
        role: 'user',
        parts: [{ text: prompt }]
      }]
    });


    return getFirestore()
    .collection("chat_sessions")
    .doc(event.params.sessionId)
    .update({
      messages: FieldValue.arrayUnion({
        content: resp.response.candidates?.[0]?.content.parts[0]?.text ||
          "I encountered an error. Please try again.",
        isUser: false,
        timestamp: admin.firestore.Timestamp.now()
      })
    });
  }
);