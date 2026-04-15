const SUPPORTED_TTS_VOICES = new Set(["coral", "alloy", "echo", "shimmer"]);
const SUPPORTED_TTS_CONTENT_TYPES = new Set(["word", "sentence"]);
const DEFAULT_TTS_VOICE = "coral";
const TTS_MODEL = "gpt-4o-mini-tts";
const DEFAULT_LANGUAGE = "fr-FR";
const TTS_RESPONSE_FORMAT = "mp3";
const TTS_SPEED = 1.15;
const MAX_TTS_INPUT_LENGTH = 800;

type ContentType = "word" | "sentence";

interface Env {
  OPENAI_API_KEY?: string;
}

interface TTSRequestBody {
  input?: unknown;
  voice?: unknown;
  language?: unknown;
  contentType?: unknown;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function buildTTSInstructions(language: string, contentType: ContentType): string {
  const normalizedLanguage = language.trim().toLowerCase();

  if (normalizedLanguage.startsWith("fr")) {
    if (contentType === "word") {
      return "Pronounce the input as a French vocabulary entry in standard French. Never interpret the spelling as English, even if it resembles an English word. Read only the provided text with natural French pronunciation and no extra words.";
    }

    return "Speak only in standard French. Read the input with natural French pronunciation. If the spelling is ambiguous, always prefer a French reading. Read only the provided text and add no extra words.";
  }

  return "Read the provided text naturally in the requested language. Read only the provided text and add no extra words.";
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders,
      });
    }

    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/api/tts") {
      return Response.json(
        { error: "Not found" },
        {
          status: 404,
          headers: corsHeaders,
        },
      );
    }

    const apiKey = env.OPENAI_API_KEY?.trim();
    if (!apiKey) {
      return Response.json(
        { error: "TTS backend is not configured." },
        {
          status: 503,
          headers: corsHeaders,
        },
      );
    }

    let requestBody: TTSRequestBody;
    try {
      requestBody = (await request.json()) as TTSRequestBody;
    } catch {
      return Response.json(
        { error: "Invalid JSON body." },
        {
          status: 400,
          headers: corsHeaders,
        },
      );
    }

    const input = typeof requestBody.input === "string" ? requestBody.input.trim() : "";
    if (!input) {
      return Response.json(
        { error: "Input text is required." },
        {
          status: 400,
          headers: corsHeaders,
        },
      );
    }

    if (input.length > MAX_TTS_INPUT_LENGTH) {
      return Response.json(
        { error: `Input text must be ${MAX_TTS_INPUT_LENGTH} characters or fewer.` },
        {
          status: 400,
          headers: corsHeaders,
        },
      );
    }

    const requestedVoice = typeof requestBody.voice === "string" ? requestBody.voice.trim() : "";
    const voice = SUPPORTED_TTS_VOICES.has(requestedVoice) ? requestedVoice : DEFAULT_TTS_VOICE;

    const requestedLanguage = typeof requestBody.language === "string"
      ? requestBody.language.trim()
      : "";
    const language = requestedLanguage || DEFAULT_LANGUAGE;

    const requestedContentType = typeof requestBody.contentType === "string"
      ? requestBody.contentType.trim()
      : "";
    const contentType = SUPPORTED_TTS_CONTENT_TYPES.has(requestedContentType)
      ? (requestedContentType as ContentType)
      : "sentence";

    const upstreamResponse = await fetch("https://api.openai.com/v1/audio/speech", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: TTS_MODEL,
        voice,
        input,
        speed: TTS_SPEED,
        instructions: buildTTSInstructions(language, contentType),
        response_format: TTS_RESPONSE_FORMAT,
      }),
    });

    if (!upstreamResponse.ok) {
      return Response.json(
        {
          error: "OpenAI TTS request failed.",
          status: upstreamResponse.status,
          requestId: upstreamResponse.headers.get("x-request-id"),
        },
        {
          status: 502,
          headers: corsHeaders,
        },
      );
    }

    const responseContentType = upstreamResponse.headers.get("content-type") ?? "audio/mpeg";

    return new Response(await upstreamResponse.arrayBuffer(), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Cache-Control": "no-store",
        "Content-Type": responseContentType,
      },
    });
  },
};
