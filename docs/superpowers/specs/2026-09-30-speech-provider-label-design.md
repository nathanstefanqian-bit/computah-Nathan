# Speech Provider Label Design

## Goal

Make the speech usage section clearly identify the configured provider.

## Behavior

- Show `Volcengine Speech Recognition` when `SPEECH_PROVIDER=volcengine`.
- Show `Deepgram Speech Recognition` when `SPEECH_PROVIDER=deepgram` or the setting is absent.
- Keep the existing waveform icon, duration, estimated CNY amount, reset action, and persisted totals.
- Do not add token counts. Volcengine ASR is duration-billed and does not report token usage.

## Implementation

Resolve the provider label from the same `SpeechProviderConfiguration` used to start speech recognition.
Pass the label into `SpeechCostView`; do not infer it from stored usage or duplicate environment parsing in the UI.

## Testing

- Verify both provider labels offline.
- Build the signed app.
- Open Debug Mode and confirm the Volcengine label renders without changing the usage total.
