# Text Entry Target Selection Design

## Goal

Make text-entry requests choose an available editor instead of repeatedly activating an already selected container.
Keep natural-language interpretation in Jev. Do not add app-specific rules, verb lists, or regular expressions.

## Observed Failure

In Notes, Accessibility exposed both:

- a selected note row with `pressClick`;
- the visible note body with `typeText`.

For the explicit request `在当前备忘录正文中输入“测试内容”`, Jev selected the already selected row.
The click produced no relevant state change, so Computah correctly stopped without replaying input.
No text reached the note body.

## Behavior

1. A request with a concrete literal value may use an offered editor's `typeText` operation.
2. `typeText` performs its own checked focus acquisition. Clicking a selected container is not a required focus step when the editor is already offered.
3. A selected control with no requested state transition is not useful merely because it is related to the intended object.
4. A request that does not provide concrete content must remain ambiguous. Computah must not invent text or reinterpret request grammar as dictated content.
5. Existing app activation, object creation, menus, and controls that genuinely reveal an absent editor remain valid prerequisites.

Examples:

- `在正文中输入“测试内容”` selects the visible editor and inserts `测试内容`.
- `帮我记一下明天交作业` may treat `明天交作业` as the supplied content.
- `写点东西` supplies no concrete content and stops for clarification.

## Implementation

Strengthen two provider-facing descriptions:

- The action-selection prompt states that an offered text-entry operation already handles focus, and an already selected container must not replace it.
- Candidate metadata states when a control is already selected and that activating it does not by itself insert text.

Do not force-select an editor in deterministic code. Jev still decides whether a click is a real prerequisite when no suitable editor is available.

## Safety

- Preserve current focus, binding, foreground-app, window, and native-surface checks.
- Do not retry an unconfirmed click.
- Do not type when value extraction is absent or ambiguous.
- Do not add Notes names, bundle IDs, command phrases, or language-specific matching.

## Tests

Offline prompt checks cover:

- explicit literal text with an offered editor and selected row;
- vague text-entry request with no supplied content;
- a selected control that genuinely needs activation because no editor is offered;
- an unrelated app with an editor to prove the rule is not Notes-specific.

One bounded live test uses a fresh empty note and explicit disposable text.
It retains the limit of three Jev requests and verifies the note body value after input.
