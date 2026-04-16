const ELEVENLABS_VOICE_MAP = new Map<string, string>([
  ["frederic", "oziFLKtaxVDHQAh7o45V"],
  ["koraly",   "F1toM6PcP54s45kOOAyV"],
  ["theodore", "hqfrgApggtO1785R4Fsn"],
  ["marie",    "sANWqF1bCMzR6eyZbCGw"],
]);
const DEFAULT_VOICE_KEY = "frederic";
const ELEVENLABS_MODEL = "eleven_turbo_v2_5";
const SUPPORTED_TTS_CONTENT_TYPES = new Set(["word", "sentence"]);
const MAX_TTS_INPUT_LENGTH = 800;

type ContentType = "word" | "sentence";

interface Env {
  ELEVENLABS_API_KEY?: string;
  TTS_CACHE?: R2Bucket;
}

interface TTSRequestBody {
  input?: unknown;
  voice?: unknown;
  contentType?: unknown;
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

    const requestedContentType = typeof requestBody.contentType === "string"
      ? requestBody.contentType.trim()
      : "";
    const contentType = SUPPORTED_TTS_CONTENT_TYPES.has(requestedContentType)
      ? (requestedContentType as ContentType)
      : "sentence";

    const stability = contentType === "word" ? 0.75 : 0.5;

    const r2Key = await computeR2Key(requestedVoice || DEFAULT_VOICE_KEY, contentType, input);

    if (env.TTS_CACHE) {
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

    const upstreamResponse = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
      {
        method: "POST",
        headers: {
          "xi-api-key": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          text: input,
          model_id: ELEVENLABS_MODEL,
          voice_settings: {
            stability,
            similarity_boost: 0.75,
          },
        }),
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

    if (env.TTS_CACHE) {
      await env.TTS_CACHE.put(r2Key, audioBuffer.slice(0), {
        httpMetadata: { contentType: "audio/mpeg" },
      });
    }

    return new Response(audioBuffer, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "audio/mpeg",
        "Cache-Control": "public, max-age=31536000",
      },
    });
  },
};

async function computeR2Key(voiceKey: string, contentType: string, input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hex = Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2, "0")).join("");
  return `${voiceKey}/${contentType}/${hex}.mp3`;
}
