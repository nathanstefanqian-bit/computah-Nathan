# OpenRouter Provider Compatibility Design

## Goal

Allow Computah to call Jev through either TypeSafe or OpenRouter without changing the command, accessibility, execution, or verification workflows.

TypeSafe remains the upstream default. This checkout will use OpenRouter because the local TypeSafe account has no credits.

## Configuration

The project-root `.env` supports:

```text
JEV_PROVIDER=typesafe|openrouter
TYPESAFE_API_KEY=
OPENROUTER_API_KEY=
DEEPGRAM_API_KEY=
```

Provider mappings are fixed in code:

| Provider | Endpoint | Model | Credential |
| --- | --- | --- | --- |
| `typesafe` | `https://api.typesafe.ai/v1/systemone` | `jev-1.13.0` | `TYPESAFE_API_KEY` |
| `openrouter` | `https://openrouter.ai/api/alpha/decisions` | `typesafe/jev-1.13` | `OPENROUTER_API_KEY` |

An absent `JEV_PROVIDER` selects `typesafe` to preserve current behavior. An unsupported value fails with a clear setup error instead of silently falling back.

## Architecture

Add a small `JevProviderConfiguration` value in `ComputahCore`. It owns only provider identity, endpoint, model, and credential environment-variable name.

`JevSelector` accepts endpoint and credential-label parameters in its initializer. Its request body, response validation, retry policy, option splitting, and safety checks remain unchanged because OpenRouter's Decisions API uses the same decision payload and answer shape.

`App` reads `JEV_PROVIDER`, resolves the corresponding key from `.env`, and creates `JevSelector` from the provider configuration. The notch setup warning checks the active provider's required key rather than always requiring `TYPESAFE_API_KEY`.

No automatic provider fallback is added. A billing, authentication, or availability error must remain visible; silently switching providers would make cost and data-routing behavior unpredictable.

## Cost Tracking

The current cost tracker recognizes only the TypeSafe model ID. Extend it to recognize both `jev-1.13.0` and `typesafe/jev-1.13` at the same published input price.

For OpenRouter responses, record provider-reported `usage.cost` as the actual request cost. Preserve provider-reported input token usage and use the published token price only as an explicitly labeled fallback when actual cost is absent.

Show request count, input tokens, and actual or estimated USD cost for each command and workflow step. Aggregate totals remain content-free and persist under ignored `outputs/`.

Every live diagnostic process has a hard limit of 3 Jev HTTP attempts, including retries. The limit is enforced at the HTTP boundary. Before a live test, report its maximum estimated Jev cost. Tests estimated above $0.005 USD require explicit user approval.

## Documentation

Update:

- `.env.example` with `JEV_PROVIDER` and `OPENROUTER_API_KEY`
- README setup instructions and provider table
- `docs/JEV_REQUESTS.md` to distinguish the two endpoint/model combinations
- `docs/TESTING.md` environment requirements

Secrets remain in ignored `.env` only.

## Testing

Add a Swift test target and focused tests for:

1. Default provider resolves to TypeSafe.
2. `openrouter` resolves to the OpenRouter endpoint, model, and credential name.
3. Unsupported provider names are rejected.
4. Cost accounting recognizes both model IDs.
5. Provider-reported cost is recorded as actual cost.
6. A fourth HTTP attempt is rejected before dispatch.
7. Existing TypeSafe defaults remain source-compatible.

Verification commands:

```text
swift test
zsh scripts/build.sh
```

After OpenRouter credits are available, run one live Decisions API request and then a low-risk Computah command against TextEdit or Notes.

## Non-goals

- Replacing Deepgram
- Adding a provider selector to the UI
- Automatic failover between providers
- Changing prompts or action-selection behavior
- Adding screenshot or vision support
- Refactoring unrelated Computah modules

## Risks

- OpenRouter may change its alpha Decisions endpoint or response shape.
- Provider-reported model IDs may differ from the requested alias and affect cost estimates.
- Live verification is blocked until the OpenRouter account has credits.

These risks are contained by explicit configuration, strict response validation, focused tests, and no silent fallback.
