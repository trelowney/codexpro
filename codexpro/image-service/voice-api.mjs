// Voice input through a Home Assistant speech-to-text engine (adopted from
// claude-code-ha 2.4.0). Speech goes only to the configured HA STT engine
// through the Supervisor. No browser-supplied URL, token, command or file path
// is accepted. Every error says what to do next.

const WHERE = 'In Home Assistant open Settings > Add-ons > Codex Pro > Configuration';
import express from 'express';

export const MAX_AUDIO_BYTES = 16000 * 2 * 60;
const PROVIDER = /^(?:stt\.)?[a-z0-9_]+$/;
const LANGUAGE = /^[a-zA-Z]{2,3}(?:[-_][a-zA-Z0-9]{2,8}){0,2}$/;

async function boundedJson(response) {
    if (!response.ok) throw new Error('upstream');
    const reader = response.body.getReader();
    const chunks = [];
    let size = 0;
    try {
        for (;;) {
            const { done, value } = await reader.read();
            if (done) break;
            size += value.length;
            if (size > 65536) throw new Error('upstream');
            chunks.push(Buffer.from(value));
        }
        return JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } finally {
        await reader.cancel().catch(() => {});
    }
}

export function register(app, {
    provider = process.env.VOICE_STT_PROVIDER || '',
    language = process.env.VOICE_LANGUAGE || '',
    token = process.env.SUPERVISOR_TOKEN || '',
    request = globalThis.fetch,
    timeoutMs = 30000,
    coreUrl = process.env.CODEXPRO_CORE_URL || 'http://supervisor/core'
} = {}) {
    provider = provider.trim();
    language = language.trim();
    const enabled = PROVIDER.test(provider) && Boolean(token);
    const endpoint = `${coreUrl}/api/stt/${encodeURIComponent(provider)}`;
    let busy = false;

    app.get('/api/voice/config', (req, res) => {
        res.set('Cache-Control', 'no-store').json({ enabled, configured: Boolean(provider), provider, language });
    });

    app.post('/api/voice/transcribe', (req, res, next) => {
        res.set('Cache-Control', 'no-store');
        // A custom header and non-simple content type prevent cross-site forms
        // from triggering recording uploads. No CORS permission is granted.
        if (req.get('X-Voice-Request') !== '1') return res.sendStatus(403);
        if (!enabled) return res.status(503).json({ error: `${WHERE} and fill in "Speech-to-text engine" (for example stt.faster_whisper), save and restart the add-on.` });
        if (busy) return res.status(409).json({ error: 'Another recording is being transcribed right now. Wait a few seconds and press Start Recording again.' });
        if (!req.is('application/octet-stream')) return res.sendStatus(415);
        busy = true;
        // Reserve before reading the body: concurrent callers cannot allocate
        // a separate full recording each. Also release on parser errors.
        res.once('close', () => { if (!res.locals.voiceProcessing) busy = false; });
        next();
    }, express.raw({ type: 'application/octet-stream', limit: MAX_AUDIO_BYTES }), async (req, res) => {
        res.locals.voiceProcessing = true;
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        const cancel = () => { if (!res.writableFinished) controller.abort(); };
        res.once('close', cancel);
        try {
            if (!Buffer.isBuffer(req.body) || req.body.length < 2 || req.body.length % 2) {
                return res.status(400).json({ error: 'The recording was empty or damaged. Press Start Recording and try again.' });
            }
            const wanted = req.get('X-Voice-Language') || language;
            if (!LANGUAGE.test(wanted)) return res.status(400).json({ error: 'Type a language code into "Speech language", for example cs, en or de-DE, and record again.' });
            const options = {
                headers: { Authorization: `Bearer ${token}` },
                redirect: 'error', signal: controller.signal
            };
            const info = await boundedJson(await request(endpoint, options));
            const normal = (code) => code.toLowerCase().replaceAll('_', '-');
            const languages = Array.isArray(info.languages) ? info.languages.filter((code) => typeof code === 'string' && LANGUAGE.test(code)) : [];
            const selected = languages.find((code) => normal(code) === normal(wanted)) ||
                languages.find((code) => normal(code) === normal(wanted).split('-')[0]) ||
                // "cs" typed, the engine only offers "cs-CZ" (Home Assistant Cloud does this)
                languages.find((code) => normal(code).split('-')[0] === normal(wanted).split('-')[0]);
            if (!selected) return res.status(400).json({ error: `This speech-to-text engine does not understand "${wanted}". Change "Speech language" to one of: ${languages.slice(0, 12).join(', ') || 'none offered'} and record again.` });
            if (!info.formats?.includes('wav') || !info.codecs?.includes('pcm') ||
                !info.sample_rates?.includes(16000) || !info.bit_rates?.includes(16) || !info.channels?.includes(1)) {
                return res.status(400).json({ error: `This speech-to-text engine cannot take browser recordings (it needs 16 kHz mono audio). ${WHERE} and choose another "Speech-to-text engine".` });
            }
            const result = await boundedJson(await request(endpoint, {
                ...options, method: 'POST', body: req.body,
                headers: {
                    ...options.headers, 'Content-Type': 'audio/wav',
                    'X-Speech-Content': `format=wav; codec=pcm; sample_rate=16000; bit_rate=16; channel=1; language=${selected}`
                }
            }));
            if (result.result !== 'success' || typeof result.text !== 'string' || result.text.length > 16000) throw new Error('upstream');
            res.json({ text: result.text });
        } catch {
            // Upstream errors can contain credentials or transcription data.
            // Return a fixed message and never log audio, text or the token.
            if (!res.destroyed) res.status(502).json({ error: `Home Assistant could not turn the recording into text. Press Start Recording to try again. If it keeps failing, check that the engine "${provider}" works in Settings > Voice assistants, or use Copy Text with your own typing instead.` });
        } finally {
            clearTimeout(timer);
            res.removeListener('close', cancel);
            busy = false;
        }
    }, (error, req, res, next) => {
        busy = false;
        if (error.type === 'entity.too.large') return res.status(413).json({ error: 'The recording was longer than 60 seconds. Record a shorter part and press Start Recording again.' });
        next(error);
    });
}
