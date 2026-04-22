# Google Dictionary Block Handling Design

**Goal:** Detect when Google dictionary requests are blocked by upstream anti-bot responses and show a clear failure state instead of misleading `No result`.

## Problem

- The Google dictionary feature uses a non-official web endpoint.
- Google can return an HTML anti-bot page with HTTP 200 instead of JSON.
- The current pipeline accepts that response as successful transport, then JSON decoding fails and the lookup silently becomes `nil`.
- `nil` is rendered as `.empty`, so the UI shows `No result` even though the real failure is upstream blocking.

## Design

### Google-Specific Response Validation

Validate Google dictionary responses after transport succeeds and before JSON decoding.

- If the response looks like HTML instead of JSON, inspect the body for known Google block-page markers.
- Return a dedicated `blockedByGoogle` error when the body matches anti-bot content.
- Return `invalidResponse` for other unexpected non-JSON payloads.

### Error Propagation

- Let Google lookup throw a typed error instead of collapsing everything to `nil`.
- Propagate that error through `DictionaryService.lookupSingle`.
- Convert that error into `.failed(message)` in the overlay pipeline.

### UI Outcome

- `No result` remains reserved for genuine empty dictionary matches.
- Google anti-bot or temporary service failures render as a descriptive failure message.

## Scope

### Included

- Detect Google block HTML.
- Propagate typed errors from the Google lookup path.
- Show a user-facing failure message in the dictionary section.
- Add regression tests for block-page detection.

### Not Included

- Retrying with captcha handling.
- Proxy rotation or other network workarounds.
- Replacing Google with a fully official API.

## Success Criteria

- When Google returns an anti-bot page, the UI no longer shows `No result`.
- Genuine empty matches still show `No result`.
- Existing non-Google dictionary behavior does not regress.
