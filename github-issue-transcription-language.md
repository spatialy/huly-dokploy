# GitHub Issue Draft: Transcription language selector is commented out — rooms always default to English

**Repository:** `hcengineering/platform`

---

## Title

Feature: Enable transcription language selector in Room settings (currently commented out)

## Labels

`enhancement`, `love`, `transcription`

## Body

### Summary

The `RoomLanguageSelector` component is **fully built and functional** — supporting 45 languages with flag emojis and native labels — but the UI row is commented out in `RoomTranscriptionSettings.svelte`, making it inaccessible to users. All rooms default to `language: 'en'` at creation time with no way to change it from the UI.

This means:
- **OpenAI STT** always receives `language: "en"`, producing garbled output and low confidence scores (~30%) for non-English speakers
- **Deepgram STT** is unaffected (hardcoded to `language: "multi"` auto-detect, ignores the room language entirely)

### Provider-specific language behavior

Even if the UI selector were enabled today, it would **only affect OpenAI STT**. Deepgram's implementation intentionally ignores the room language:

| Behavior | OpenAI STT | Deepgram STT |
|----------|-----------|--------------|
| **Language default** | `"en"` (stored on instance) | N/A — hardcoded `"multi"` in `getOptions()` |
| **`updateLanguage()` behavior** | Stores new language, sends live `transcription_session.update` to all active WebSocket connections (gated by `OPENAI_PROVIDE_LANGUAGE`) | **No-op** — method body is entirely commented out |
| **Language sent to API** | `this.language` (dynamic, from room metadata) or `undefined` if `OPENAI_PROVIDE_LANGUAGE=false` | Always `"multi"` (hardcoded), regardless of room setting |
| **`OPENAI_PROVIDE_LANGUAGE` effect** | Controls whether language hint is included in initial session and live updates | No effect whatsoever |
| **Auto-detection** | Only when language is omitted (`OPENAI_PROVIDE_LANGUAGE=false`) | Always — Nova-3 `"multi"` mode handles multilingual automatically |
| **Mid-meeting language change** | Works — sends `transcription_session.update` in real-time | Would require connection restart (code exists but is commented out) |

The Deepgram `updateLanguage()` originally had a stop/restart implementation to reconnect with the new language, but it was commented out — likely because Nova-3's `"multi"` mode already handles multilingual meetings well without explicit hints.

### The infrastructure is complete

The full language pipeline already works end-to-end:

| Layer | Status | Details |
|-------|--------|---------|
| **Types** | Done | `RoomLanguage` union type with 45 languages, `languagesDisplayData` with flag emojis |
| **Room schema** | Done | `Room.language: RoomLanguage` field persisted in DB |
| **UI component** | Done | `RoomLanguageSelector.svelte` — dropdown with search, two display modes |
| **Settings popup** | **Commented out** | `RoomTranscriptionSettings.svelte` lines ~30-35 |
| **Room creation** | Hardcoded `'en'` | `AddRoomPopup.svelte` — `language: 'en'` |
| **Metadata flow** | Done | `startTranscription()` → `connectMeeting(room.language)` → aibot → love → LiveKit metadata |
| **Love service** | Done | `/transcription` and `/language` endpoints update room metadata |
| **Love-agent** | Done | `RoomMetadataChanged` → `stt.updateLanguage()` |
| **OpenAI STT** | Done | `transcription_session.update` with new language, works dynamically mid-meeting |
| **Deepgram STT** | N/A | `updateLanguage()` is a no-op, always uses `"multi"` |

### Where the code is commented out

**`plugins/love-resources/src/components/RoomTranscriptionSettings.svelte`:**

```svelte
<!-- <div class="antiGrid-row">
    <div class="antiGrid-row__header">
      <Label label={ui.string.Language} />
    </div>
    <RoomLanguageSelector {room} />
  </div> -->
```

**`plugins/love-resources/src/components/AddRoomPopup.svelte`:**

```ts
language: 'en',  // hardcoded, no language picker in room creation dialog
```

### Impact on self-hosted deployments

Self-hosted users deploying with OpenAI STT in non-English environments get:
- Low confidence transcriptions (30-50% probability)
- Garbled text for non-English speech
- No way to fix it without code changes or switching to Deepgram

### Proposed fix

1. **Uncomment** the language selector in `RoomTranscriptionSettings.svelte`
2. **Add** a language picker to `AddRoomPopup.svelte` (default to browser locale or `'en'`)
3. **Uncomment** the `updateLanguage()` implementation in `deepgram/stt.ts` — this would allow Deepgram users to override `"multi"` auto-detect with a specific language when needed (e.g., single-language meetings where auto-detect is less accurate)
4. (Optional) Consider making the language selector show a note indicating that Deepgram always auto-detects, so users understand the selector primarily affects OpenAI STT

### Workarounds

- **Switch to Deepgram** (`STT_PROVIDER=deepgram`) — uses `language: "multi"` auto-detect, works for all languages
- **Set `OPENAI_PROVIDE_LANGUAGE=false`** on the love-agent — disables the English hint, lets OpenAI auto-detect (less accurate than an explicit language hint)
- **Direct DB update** — `UPDATE love SET data = jsonb_set(data, '{language}', '"es"') WHERE _class = 'love:class:Room'` (requires CockroachDB access)

### Additional note: probability/perplexity in transcripts

The OpenAI STT appends `(probability, perplexity)` metrics to each transcript line (e.g., `"Hello world. (0.95, 1.05)"`). These are computed from logprobs and stored as part of the transcript text in MeetingMinutes. This is useful for debugging but may confuse end users. Consider either:
- Storing these as separate metadata fields rather than appending to the text
- Making the inclusion configurable via an env var

### Environment

- **Version:** v0.7.353 (`hardcoreeng/*` images)
- **STT Provider:** OpenAI (Realtime API, `gpt-4o-transcribe`)
- **Deployment:** Self-hosted via Docker Compose
