import { $Database, $Env, OpenApiExtension, PocketUIExtension, teenyHono } from 'teenybase/worker';
import config from '../migrations/config.json';
import { DatabaseSettings } from "teenybase";

const ELEVENLABS_VOICE_MAP = new Map<string, string>([
  ['frederic', 'oziFLKtaxVDHQAh7o45V'],
  ['koraly', 'F1toM6PcP54s45kOOAyV'],
  ['theodore', 'hqfrgApggtO1785R4Fsn'],
  ['marie', 'sANWqF1bCMzR6eyZbCGw'],
]);
const DEFAULT_VOICE_KEY = 'frederic';
const ELEVENLABS_MODEL = 'eleven_turbo_v2_5';
const SUPPORTED_TTS_CONTENT_TYPES = new Set(['word', 'sentence']);
const MAX_TTS_INPUT_LENGTH = 800;

export interface Env {
  Bindings: $Env['Bindings'] & {
    PRIMARY_DB: D1Database;
    PRIMARY_R2?: R2Bucket;
    ELEVENLABS_API_KEY?: string;
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
  const apiKey = c.env.ELEVENLABS_API_KEY?.trim();
  if (!apiKey) {
    return c.json({ error: 'TTS backend is not configured.' }, 503);
  }

  let requestBody: { input?: unknown; voice?: unknown; contentType?: unknown; cachePolicy?: unknown };
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
    ? requestBody.voice.trim().toLowerCase()
    : '';
  const voiceId = ELEVENLABS_VOICE_MAP.get(requestedVoice) ?? ELEVENLABS_VOICE_MAP.get(DEFAULT_VOICE_KEY)!;

  const requestedContentType = typeof requestBody.contentType === 'string'
    ? requestBody.contentType.trim()
    : '';
  const contentType = SUPPORTED_TTS_CONTENT_TYPES.has(requestedContentType)
    ? requestedContentType as 'word' | 'sentence'
    : 'sentence';

  const stability = contentType === 'word' ? 0.75 : 0.5;

  const upstreamResponse = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
    {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
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
    return c.json({
      error: 'ElevenLabs TTS request failed.',
      status: upstreamResponse.status,
    }, 502);
  }

  const audioData = await upstreamResponse.arrayBuffer();

  return new Response(audioData, {
    status: 200,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'audio/mpeg',
    },
  });
})

export default app
