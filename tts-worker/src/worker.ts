const ELEVENLABS_VOICE_MAP = new Map<string, string>([
  ["frederic", "oziFLKtaxVDHQAh7o45V"],
  ["koraly",   "F1toM6PcP54s45kOOAyV"],
  ["theodore", "hqfrgApggtO1785R4Fsn"],
  ["marie",    "sANWqF1bCMzR6eyZbCGw"],
]);
const DEFAULT_VOICE_KEY = "frederic";
const DEFAULT_LANGUAGE_CODE = "fr";
const ELEVENLABS_MODEL = "eleven_turbo_v2_5";
const TTS_GENERATION_PROFILE = "fr-word-alias-v1";
const SUPPORTED_TTS_CONTENT_TYPES = new Set(["word", "sentence"]);
const MAX_TTS_INPUT_LENGTH = 800;
const FRENCH_WORD_TTS_ALIASES = new Map<string, string>([
  ["rugby", "rugbi"],
]);

type ContentType = "word" | "sentence";

interface Env {
  ELEVENLABS_API_KEY?: string;
  TTS_CACHE?: R2Bucket;
}

interface TTSRequestBody {
  input?: unknown;
  voice?: unknown;
  language?: unknown;
  contentType?: unknown;
  cachePolicy?: unknown;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
        { status: 404, headers: corsHeaders },
      );
    }

    const apiKey = env.ELEVENLABS_API_KEY?.trim();
    if (!apiKey) {
      return Response.json(
        { error: "TTS backend is not configured." },
        { status: 503, headers: corsHeaders },
      );
    }

    let requestBody: TTSRequestBody;
    try {
      requestBody = (await request.json()) as TTSRequestBody;
    } catch {
      return Response.json(
        { error: "Invalid JSON body." },
        { status: 400, headers: corsHeaders },
      );
    }

    const input = typeof requestBody.input === "string" ? requestBody.input.trim() : "";
    if (!input) {
      return Response.json(
        { error: "Input text is required." },
        { status: 400, headers: corsHeaders },
      );
    }

    if (input.length > MAX_TTS_INPUT_LENGTH) {
      return Response.json(
        { error: `Input text must be ${MAX_TTS_INPUT_LENGTH} characters or fewer.` },
        { status: 400, headers: corsHeaders },
      );
    }

    const requestedVoice = typeof requestBody.voice === "string" ? requestBody.voice.trim().toLowerCase() : "";
    const voiceId = ELEVENLABS_VOICE_MAP.get(requestedVoice) ?? ELEVENLABS_VOICE_MAP.get(DEFAULT_VOICE_KEY)!;
    const languageCode = normalizeLanguageCode(requestBody.language);

    const requestedContentType = typeof requestBody.contentType === "string"
      ? requestBody.contentType.trim()
      : "";
    const contentType = SUPPORTED_TTS_CONTENT_TYPES.has(requestedContentType)
      ? (requestedContentType as ContentType)
      : "sentence";

    const stability = contentType === "word" ? 0.75 : 0.5;
    const requestedCachePolicy = typeof requestBody.cachePolicy === "string"
      ? requestBody.cachePolicy.trim().toLowerCase()
      : "default";
    const bypassCache = requestedCachePolicy === "bypass";

    const r2Key = bypassCache
      ? ""
      : await computeR2Key(
        requestedVoice || DEFAULT_VOICE_KEY,
        languageCode,
        contentType,
        TTS_GENERATION_PROFILE,
        input,
      );

    if (!bypassCache && env.TTS_CACHE) {
      const cached = await env.TTS_CACHE.get(r2Key);
      if (cached) {
        return new Response(cached.body, {
          status: 200,
          headers: {
            ...corsHeaders,
            "Content-Type": "audio/mpeg",
            "Cache-Control": "public, max-age=31536000",
          },
        });
      }
    }

    const speechInput = pronunciationInputFor(input, languageCode, contentType);

    const upstreamResponse = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
      {
        method: "POST",
        headers: {
          "xi-api-key": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(makeElevenLabsRequestBody(speechInput, languageCode, contentType, stability)),
      },
    );

    if (!upstreamResponse.ok) {
      return Response.json(
        {
          error: "ElevenLabs TTS request failed.",
          status: upstreamResponse.status,
        },
        { status: 502, headers: corsHeaders },
      );
    }

    const audioBuffer = await upstreamResponse.arrayBuffer();

    if (!bypassCache && env.TTS_CACHE) {
      await env.TTS_CACHE.put(r2Key, audioBuffer.slice(0), {
        httpMetadata: { contentType: "audio/mpeg" },
      });
    }

    return new Response(audioBuffer, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "audio/mpeg",
        "Cache-Control": bypassCache ? "no-store" : "public, max-age=31536000",
      },
    });
  },
};

function pronunciationInputFor(input: string, languageCode: string, contentType: ContentType): string {
  if (contentType !== "word" || languageCode !== "fr") {
    return input;
  }

  const normalizedInput = input.trim().toLowerCase();
  return FRENCH_WORD_TTS_ALIASES.get(normalizedInput) ?? input;
}

function makeElevenLabsRequestBody(
  input: string,
  languageCode: string,
  contentType: ContentType,
  stability: number,
) {
  const body: Record<string, unknown> = {
    text: input,
    model_id: ELEVENLABS_MODEL,
    language_code: languageCode,
    voice_settings: {
      stability,
      similarity_boost: 0.75,
    },
  };

  if (contentType === "word" && languageCode === "fr") {
    body.previous_text = "Voici le mot français :";
    body.next_text = ".";
  }

  return body;
}

function normalizeLanguageCode(language: unknown): string {
  if (typeof language !== "string") {
    return DEFAULT_LANGUAGE_CODE;
  }

  const requestedLanguage = language.trim().toLowerCase();
  if (!requestedLanguage) {
    return DEFAULT_LANGUAGE_CODE;
  }

  return requestedLanguage.split(/[-_]/)[0] || DEFAULT_LANGUAGE_CODE;
}

async function computeR2Key(
  voiceKey: string,
  languageCode: string,
  contentType: string,
  generationProfile: string,
  input: string,
): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hex = Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, "0")).join("");
  return `${voiceKey}/${languageCode}/${contentType}/${generationProfile}/${hex}.mp3`;
}
