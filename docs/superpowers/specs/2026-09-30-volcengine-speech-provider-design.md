# Volcengine Speech Provider Design

## Goal

Add Volcengine Doubao streaming speech recognition to Computah while retaining Deepgram as a configurable fallback.
Volcengine becomes the default speech provider after credentials are configured.

## Model Selection

Public sources do not identify the exact internal model ID used by Doubao Input Method.
The closest documented service is **Doubao Streaming Speech Recognition Model 2.0**, which Volcengine explicitly recommends for new integrations and lists for voice-input-method scenarios.

- Resource ID: `volc.seedasr.sauc.duration`
- Endpoint: `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`
- Model name: `bigmodel`
- Billing: duration-based, currently documented at 1 CNY/hour for pay-as-you-go

The integration uses the optimized bidirectional streaming endpoint with second-pass recognition enabled.

## Configuration

```dotenv
SPEECH_PROVIDER=volcengine
VOLCENGINE_SPEECH_API_KEY=
VOLCENGINE_SPEECH_RESOURCE_ID=volc.seedasr.sauc.duration
DEEPGRAM_API_KEY=
```

`SPEECH_PROVIDER` accepts `volcengine` and `deepgram`.
An absent value preserves the existing Deepgram default until the migration is explicitly activated.
Credentials remain only in the ignored root `.env` file with mode `0600`.

## Architecture

Split the current `Voice` responsibilities into:

1. Microphone capture and PCM16 conversion shared by all providers.
2. A speech-provider session interface that accepts PCM chunks and emits interim text, final text, status, and usage.
3. A Deepgram adapter containing the existing JSON WebSocket behavior.
4. A Volcengine adapter containing authentication headers, binary framing, gzip payload handling, and response decoding.

The app-facing callbacks remain stable so command coordination and UI code do not depend on a provider protocol.

## Volcengine Data Flow

1. Capture mono PCM16 audio at 16 kHz.
2. Send approximately 200 ms per packet.
3. Authenticate with `X-Api-Key`, `X-Api-Resource-Id`, and a unique request ID.
4. Request:
   - `enable_nonstream=true`
   - `enable_itn=true`
   - `enable_punc=true`
   - `enable_ddc=true`
   - `show_utterances=true`
   - `end_window_size=800`
5. Display interim recognition immediately.
6. Use a provider `prefetch` hint to prepare a read-only Jev plan.
7. Submit to Computah only after Volcengine returns a definite second-pass result.

Prefetch planning never sends app input. If later interim text changes, Computah cancels the
speculative plan. A definite result may reuse it only when the text is exact or differs solely
by trailing punctuation, and only for a plan without a literal input value.

## Cost Control

Track each Volcengine session using provider-reported audio duration.
Show session duration and a clearly labeled cost estimate using the configured CNY/hour price.
Do not present this estimate as an account invoice.

Every live speech test must:

- contain at most 30 seconds of supplied audio;
- state the maximum speech cost before execution;
- retain the existing hard limit of 3 Jev HTTP attempts;
- stop instead of automatically retrying with Deepgram.

At the documented 1 CNY/hour rate, a 30-second test costs at most about 0.0083 CNY for speech recognition, excluding Jev.

## Failure Handling

- Missing provider credentials stop before opening a WebSocket.
- Authentication and entitlement failures display the provider error without fallback.
- Malformed or out-of-order packets are rejected.
- Audio transport loss invalidates the active turn so stale text cannot execute.
- Empty and non-definite transcripts never reach the command coordinator.
- Provider logs may store request IDs and status codes, but never API keys or microphone audio.

## Testing

Offline checks cover:

- provider configuration and credential selection;
- Volcengine binary frame encode/decode fixtures;
- gzip and uncompressed payload handling;
- interim versus definite transcript mapping;
- empty transcript rejection;
- stale and out-of-order response rejection;
- 30-second diagnostic audio limit;
- Deepgram compatibility.

One user-approved live test validates authentication, final Chinese transcription, duration accounting, and a real command. It must stay within 30 seconds of audio and 3 Jev calls.

## Rollout

1. Implement and pass all offline checks.
2. Create or select a restricted Volcengine speech API key.
3. Confirm the account's actual free quota or billing state in the console.
4. Set `SPEECH_PROVIDER=volcengine`.
5. Run one bounded live test and compare its transcript with Deepgram only if the user separately authorizes another paid test.

## Non-Goals

- Claiming parity with Doubao Input Method's undisclosed internal stack.
- Using the end-to-end conversational speech model.
- Automatically purchasing resources or enabling postpaid billing.
- Sending one audio stream to both providers.
