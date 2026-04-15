import { $Database, $Env, OpenApiExtension, PocketUIExtension, teenyHono } from 'teenybase/worker';
import config from '../migrations/config.json';
import { DatabaseSettings } from "teenybase";

const SUPPORTED_TTS_VOICES = new Set(['coral', 'alloy', 'echo', 'shimmer']);
const SUPPORTED_TTS_CONTENT_TYPES = new Set(['word', 'sentence']);
const DEFAULT_TTS_VOICE = 'coral';
const TTS_MODEL = 'gpt-4o-mini-tts';
const TTS_INSTRUCTIONS = 'Parle uniquement en français. Si le texte contient une autre langue, lis-le avec une prononciation française.';
const TTS_RESPONSE_FORMAT = 'mp3';
const TTS_SPEED = 1.15;
const MAX_TTS_INPUT_LENGTH = 800;

function buildTTSInstructions(language: string, contentType: 'word' | 'sentence'): string {
  const normalizedLanguage = language.trim().toLowerCase();

  if (normalizedLanguage.startsWith('fr')) {
    if (contentType === 'word') {
      return 'Tu prononces une carte de vocabulaire française. Prononce toujours l’entrée comme un mot ou une locution française du français standard. N’interprète jamais l’orthographe comme de l’anglais, même si elle ressemble à un mot anglais. Lis uniquement l’entrée reçue, sans ajouter de préambule.';
    }

    return 'Parle uniquement en français standard. Lis l’entrée avec une prononciation française naturelle. Si une graphie est ambiguë, privilégie systématiquement la lecture française. Lis uniquement l’entrée reçue, sans ajouter de préambule.';
  }

  return TTS_INSTRUCTIONS;
}

export interface Env {
  Bindings: $Env['Bindings'] & {
    PRIMARY_DB: D1Database;
    PRIMARY_R2?: R2Bucket;
    OPENAI_API_KEY?: string;
  },
  Variables: $Env['Variables']
}

const app = teenyHono<Env>(async (c)=> {
  const db = new $Database(c, config as unknown as DatabaseSettings, c.env.PRIMARY_DB, c.env.PRIMARY_R2)
  db.extensions.push(new OpenApiExtension(db, true))
  db.extensions.push(new PocketUIExtension(db))

  return db
}, undefined, {
  logger: false,
  cors: true,
})

app.get('/', (c)=>{
  return c.json({message: 'Hello Hono'})
})

app.post('/api/tts', async (c) => {
  const apiKey = c.env.OPENAI_API_KEY?.trim();
  if (!apiKey) {
    return c.json({ error: 'TTS backend is not configured.' }, 503);
  }

  let requestBody: { input?: unknown; voice?: unknown; language?: unknown; contentType?: unknown };
  try {
    requestBody = await c.req.json();
  } catch {
    return c.json({ error: 'Invalid JSON body.' }, 400);
  }

  const input = typeof requestBody.input === 'string'
    ? requestBody.input.trim()
    : '';
  if (!input) {
    return c.json({ error: 'Input text is required.' }, 400);
  }
  if (input.length > MAX_TTS_INPUT_LENGTH) {
    return c.json({ error: `Input text must be ${MAX_TTS_INPUT_LENGTH} characters or fewer.` }, 400);
  }

  const requestedVoice = typeof requestBody.voice === 'string'
    ? requestBody.voice.trim()
    : '';
  const voice = SUPPORTED_TTS_VOICES.has(requestedVoice)
    ? requestedVoice
    : DEFAULT_TTS_VOICE;

  const requestedLanguage = typeof requestBody.language === 'string'
    ? requestBody.language.trim()
    : '';
  const language = requestedLanguage || 'fr-FR';

  const requestedContentType = typeof requestBody.contentType === 'string'
    ? requestBody.contentType.trim()
    : '';
  const contentType = SUPPORTED_TTS_CONTENT_TYPES.has(requestedContentType)
    ? requestedContentType as 'word' | 'sentence'
    : 'sentence';

  const upstreamResponse = await fetch('https://api.openai.com/v1/audio/speech', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
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
    return c.json({
      error: 'OpenAI TTS request failed.',
      status: upstreamResponse.status,
      requestId: upstreamResponse.headers.get('x-request-id'),
    }, 502);
  }

  const audioData = await upstreamResponse.arrayBuffer();
  const responseContentType = upstreamResponse.headers.get('content-type') ?? 'audio/mpeg';

  return new Response(audioData, {
    status: 200,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': responseContentType,
    },
  });
})

export default app
