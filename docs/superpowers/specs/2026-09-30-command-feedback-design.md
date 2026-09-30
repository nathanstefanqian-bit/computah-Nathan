# Command Feedback Design

## Goal

Always show visible feedback after a spoken command is submitted.
Do not leave the last transcript on screen when Computah is working, paused, blocked, failed, or complete.

## Behavior

- While speech is being recognized, the notch shows the current transcript.
- After final submission, it shows the current execution status.
- A completed, stopped, ambiguous, or failed command leaves its final status visible.
- Starting a new speech turn clears the prior feedback and returns to transcript display.
- Debug Mode continues to show status and transcript separately.

Feedback is a separate state channel from transcript text. It is not inferred by matching status strings.

## Ambiguous Destinations

A send request without a named recipient may use a positively identified currently open conversation.
Computah must not search for or infer another recipient.
If no current conversation is identifiable, it stops and asks the user to specify the target.

## Safety

- Feedback never authorizes input.
- Existing native binding, focus, and verification checks remain unchanged.
- No app name, bundle ID, command phrase, or language-specific pattern controls behavior.

## Verification

- Offline checks cover feedback lifecycle and prompt constraints.
- The signed app build must pass.
- Live message sending requires separate explicit authorization because it transmits data to another person.
