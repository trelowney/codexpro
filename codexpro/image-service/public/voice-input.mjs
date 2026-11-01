// Voice input (adopted from claude-code-ha 2.4.0): a Home Assistant
// speech-to-text engine when one is set in the add-on options, otherwise the
// browser's own speech service. The Record button is never greyed out: a click
// always either works or says what is missing and where to set it.
import { recordAudio, terminalText } from './voice-audio.mjs';

const WHERE = 'In Home Assistant open Settings > Add-ons > Codex Pro > Configuration';

const get = (id) => document.getElementById(`voice-${id}`);
const modal = get('modal');
const status = get('status');
const transcript = get('transcript');
const record = get('record-btn');
const copy = get('copy-btn');
const send = get('send-btn');
const language = get('language');
const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
let config = null;
let active = null;
let generation = 0;
let state = 'idle';

function message(text) { status.textContent = text; }
function update() {
    record.textContent = state === 'recording' ? 'Stop Recording' : state === 'transcribing' ? 'Transcribing…' : 'Start Recording';
    language.disabled = state !== 'idle';
    const ready = state === 'idle' && Boolean(transcript.textContent.trim());
    copy.style.display = send.style.display = ready ? 'inline-block' : 'none';
    transcript.classList.toggle('listening', state === 'recording');
    get('btn').classList.toggle('recording', state === 'recording');
}

function cancel() {
    generation++;
    active?.controller.abort();
    active?.audio?.cancel();
    active?.recognition?.abort();
    clearTimeout(active?.timer);
    active = null;
    state = 'idle';
    update();
}
function close() { cancel(); modal.classList.remove('active'); }
function intro() {
    if (config.enabled) return `Press Start Recording and speak (up to 60 seconds). Home Assistant (${config.provider}) turns it into text.`;
    if (config.configured) return `The speech-to-text engine "${config.provider}" is not a valid name. ${WHERE} and fill in "Speech-to-text engine" with its entity ID, for example stt.faster_whisper (Settings > Voice assistants lists them). Then restart the add-on.`;
    if (SpeechRecognition) return 'Press Start Recording and speak. Your browser turns it into text.';
    return `This browser cannot turn speech into text by itself. ${WHERE} and fill in "Speech-to-text engine" (for example stt.faster_whisper), then restart the add-on. Until then, type into the terminal.`;
}

get('btn').addEventListener('click', async () => {
    cancel();
    modal.classList.add('active');
    record.focus();
    transcript.textContent = '';
    update();
    if (!config) {
        const id = generation;
        try {
            const response = await fetch('api/voice/config', { cache: 'no-store' });
            if (!response.ok) throw new Error();
            const value = await response.json();
            if (id !== generation) return;
            config = value;
            // some browsers report e.g. "en-US@posix" or "cs_CZ.UTF-8": keep only the language code
            language.value = config.language || (navigator.language || '').split(/[@.]/)[0] || 'en-US';
        } catch {
            if (id === generation) message('Could not load the voice settings. Press Close and then 🎤 Voice Input again. If that does not help, restart the add-on.');
            return;
        }
    }
    message(intro());
    update();
});

get('close-btn').addEventListener('click', close);
modal.addEventListener('click', (event) => { if (event.target === modal) close(); });
// Escape closes the window wherever the keyboard focus is (like the Copy window)
document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && modal.classList.contains('active')) close(); });
window.addEventListener('pagehide', cancel);
transcript.addEventListener('input', update);

record.addEventListener('click', async () => {
    if (state === 'recording') { await stop(); return; }
    if (state === 'starting') { message('Waiting for the microphone. If the browser asks, press Allow.'); return; }
    if (state === 'transcribing') { message('Turning the recording into text, a few seconds please…'); return; }
    if (!config) { message('The voice settings did not load. Press Close and then 🎤 Voice Input again.'); return; }
    if (config.configured && !config.enabled) { message(intro()); return; }
    if (!/^[a-zA-Z]{2,3}(?:[-_][a-zA-Z0-9]{2,8}){0,2}$/.test(language.value.trim())) {
        message('Type a language code into "Speech language", for example cs, en or de-DE, then press Start Recording.');
        language.focus();
        return;
    }
    if (!window.isSecureContext) {
        message('The microphone only works when Home Assistant is opened over HTTPS (an address starting with https://). Open it that way, or use the Home Assistant app with its remote (https) address.');
        return;
    }
    if (!config.enabled && !SpeechRecognition) { message(intro()); return; }
    const session = { id: ++generation, controller: new AbortController() };
    active = session;
    state = 'starting';
    transcript.textContent = '';
    message('Requesting microphone access…');
    update();
    try {
        if (config.enabled) {
            if (!navigator.mediaDevices?.getUserMedia || !window.AudioWorkletNode) {
                throw new Error('This browser cannot record audio. Use a current Chrome, Edge, Firefox or Safari, or the Home Assistant app, opened over HTTPS.');
            }
            session.audio = await recordAudio(() => { if (state === 'recording') void stop(); }, session.controller.signal);
            if (session.id !== generation) { session.audio.cancel(); return; }
        } else {
            const recognition = session.recognition = new SpeechRecognition();
            recognition.lang = language.value.trim();
            recognition.continuous = true;
            recognition.interimResults = true;
            recognition.onresult = (event) => {
                if (session.id !== generation) return;
                // Read the entire result list: interim results can be revised.
                transcript.textContent = Array.from(event.results).map((result) => result[0].transcript).join(' ');
            };
            recognition.onerror = (event) => {
                if (session.id !== generation) return;
                cancel();
                message(event.error === 'not-allowed'
                    ? 'The microphone is blocked. Allow it for this page (the lock icon next to the address, or the Home Assistant app settings) and press Start Recording again.'
                    : `The browser could not turn speech into text. Press Start Recording to try again. If it keeps failing: ${WHERE} and fill in "Speech-to-text engine".`);
            };
            recognition.onend = () => {
                if (session.id !== generation) return;
                clearTimeout(session.timer);
                state = 'idle';
                active = null;
                message(transcript.textContent.trim() ? 'Done. Check the text, fix it if needed, then press Insert in Terminal.' : 'Nothing was recognised. Press Start Recording and speak a little louder.');
                update();
            };
            recognition.start();
            session.timer = setTimeout(() => { if (state === 'recording') void stop(); }, 60000);
        }
        state = 'recording';
        message('Listening… Press Stop Recording when finished.');
        update();
    } catch (error) {
        if (session.id !== generation) return;
        cancel();
        message(error.name === 'NotAllowedError'
            ? 'The microphone is blocked. Allow it for this page (the lock icon next to the address, or the Home Assistant app settings) and press Start Recording again.'
            : `${error.message || 'Recording could not start.'} Press Start Recording to try again.`);
    }
});

async function stop() {
    const session = active;
    if (!session || state !== 'recording') return;
    state = 'transcribing';
    update();
    if (session.recognition) { session.recognition.stop(); return; }
    message('Turning the recording into text, a few seconds please…');
    const timer = setTimeout(() => session.controller.abort(), 35000);
    try {
        const audio = await session.audio.stop();
        if (session.id !== generation) return;
        const response = await fetch('api/voice/transcribe', {
            method: 'POST', signal: session.controller.signal,
            headers: { 'Content-Type': 'application/octet-stream', 'X-Voice-Request': '1', 'X-Voice-Language': language.value.trim() },
            body: audio
        });
        const result = await response.json();
        if (session.id !== generation) return;
        if (!response.ok) throw new Error(result.error || 'Home Assistant could not turn the recording into text. Press Start Recording to try again.');
        transcript.textContent = result.text;
        message(result.text.trim() ? 'Done. Check the text, fix it if needed, then press Insert in Terminal.' : 'Nothing was recognised. Press Start Recording and speak a little louder.');
    } catch (error) {
        if (session.id === generation) message(error.name === 'AbortError'
            ? 'That took too long. Record a shorter part and press Start Recording again.'
            : error.name === 'SyntaxError' ? 'The add-on did not answer properly. Press Start Recording to try again; if it keeps happening, restart the add-on.'
            : error.message);
    } finally {
        clearTimeout(timer);
        if (session.id === generation) { active = null; state = 'idle'; update(); }
    }
}

copy.addEventListener('click', async () => {
    const ok = await window.copyToClipboard(transcript.textContent.trim());
    message(ok ? 'Copied. Paste it wherever you need it.' : 'The browser blocked copying. Select the text above with the mouse or finger and copy it by hand.');
});
send.addEventListener('click', () => {
    const text = terminalText(transcript.textContent);
    if (!text) { message('There is no text to insert. Press Start Recording first, or type into the box above.'); return; }
    try {
        const term = document.getElementById('terminal-frame').contentWindow.term;
        if (typeof term?.paste !== 'function') throw new Error();
        term.paste(text);
        close();
        term.focus();
    } catch { message('The terminal is not ready. Press Copy Text, close this window and paste with Ctrl+V.'); }
});
update();
