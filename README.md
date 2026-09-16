# Lather

A native macOS SOAP client, built in SwiftUI. Think Postman/Insomnia/Bruno, but for SOAP — with a focus on real-world cases like AFIP/WSAA integrations (Argentine electronic invoicing) and other legacy `rpc/encoded` services.

Prioritizes performance and native Apple components (AppKit under the hood for the code editors) instead of an Electron-style wrapper.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+

## Running it

Open `lather.xcodeproj` in Xcode and run the `lather` target (⌘R). No external dependencies or package manager — it's a plain Xcode project using "synchronized folder groups" (any `.swift` file added under `lather/` is automatically picked up by the target).

## What's in it today

### Vault
On first launch, Lather asks you to choose a folder — the "vault" — where it stores your collections and requests. You can pick any folder or use the default location (inside the app's own container). The chosen folder is remembered via a security-scoped bookmark, so it reopens automatically on every later launch without asking again. Its path is shown in Settings, with a "Reveal in Finder" shortcut.

It's a real, browsable folder tree, not one opaque file — the same idea as a Bruno collection:

```
<vault>/Collections/
  AFIP WSAA/
    .collection.json     — {"id", "name"}: identity/name (folder names are
                            just for Finder — sanitized and de-duplicated)
    LoginCms.json         — the full request
  epagos/
    obtener_token.json
    solicitud_pago.json
```

Saving fully rewrites `Collections/` from the in-memory state each time, so a rename or delete never leaves an orphaned file behind — nothing outside that folder in your vault is ever touched. Two collections/requests that end up with the same on-disk name (e.g. after sanitizing invalid characters) get a `(2)`, `(3)`, ... suffix on disk only; their display name stays exactly what you typed.

Edits save automatically: rapid changes (typing in the body editor) are debounced to one disk write shortly after you pause, and everything is flushed immediately when you switch requests or the app loses focus/quits — so nothing is lost mid-edit.

### Collections & import
- Sidebar with collapsible collections (folders) and requests.
- Create/rename/delete collections and requests from context menus.
- **Real import** from:
  - **WSDL** — parses `<message>`/`<part>` and the `<xsd:complexType>` definitions in `<types>` to generate, for each operation in the `<binding>`, an example SOAP envelope with all the real fields (types, arrays, nested objects), not just the operation name.
  - **Postman Collection** (v2.1) and **Insomnia** (v4 export) — flattens folders, splits the `SOAPAction` header out from the rest.

### The 3 payload layers of a request
Each request's editor has three tabs:

1. **Schema** — read-only. The "official" envelope generated from the WSDL (if the request came from a WSDL import); serves as a reference and powers autocomplete.
2. **XML** — the actual envelope sent over HTTP. Editable, with syntax highlighting, live validation (line/column of the error), tag/quote auto-closing, and auto-indent.
3. **JSON** — a clean translation of the XML (stripped of the `soapenv:Envelope`/`Header`/`Body` noise). Also editable: whatever you change here gets translated back into the XML, which stays the source of truth.

Both code editors (XML and JSON) are built directly on `NSTextView` (not SwiftUI's `TextEditor`), because they need real control over the cursor and layout to highlight syntax without resetting the cursor position, intercept keystrokes for auto-closing, and draw line numbers that stay in sync with actual scrolling (via `NSRulerView`, the same way Xcode does it).

### Autocomplete
`Control+Space` triggers macOS's native completion (the same mechanism Xcode/TextEdit use), suggesting field names pulled from the WSDL schema. If the request didn't come from a WSDL, there's nothing to suggest — harmless, it just offers nothing.

> Note: `Control+Space` is also macOS's default Spotlight shortcut. If you still have it bound that way, the system may grab the keystroke before it reaches the app.

### Sending requests
- Real `POST` (`URLSession`) to the request's endpoint, with Layer 2's XML as-is, headers (`Content-Type`, quoted `SOAPAction`, plus any custom ones), and the body.
- The response (status, headers, raw XML, JSON translation) shows up in the bottom panel.
- **Timeline**: every send gets logged — what went out (headers, body) and what came back (status, headers, body), per request. Switching to another request in the sidebar doesn't wipe the one you left.

### Certificates (mTLS) — partial
There's structure in place to attach client certificates (`.pem`/`.crt`/`.key`) per request, meant for cases like a WSAA access ticket. **It's not wired up to the actual TLS handshake yet** — that still needs converting those PEM files into a `SecIdentity` and building the `URLSessionDelegate` that responds to the client-certificate challenge. Requests currently go out without the certificate even if one is selected.

### Command Center (⌘K)
Centered command bar in the toolbar, Cursor/VS Code style:
- Searches requests by name across every collection.
- Runs quick commands by typing part of their name: "New Collection", "New Request", "Settings".
- Keyboard navigation with ↓/↑, Enter to run, Escape to dismiss.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘Return | Send the request |
| ⌘1 / ⌘2 / ⌘3 | Switch Schema / XML / JSON tab |
| ⌘N | New collection |
| ⌘⇧N | New request (in the first available collection) |
| ⌘K | Focus the Command Center |
| ⌘, | Open Settings |
| Control+Space | Autocomplete (inside the XML/JSON editors) |

## Architecture

MVVM using [`Observation`](https://developer.apple.com/documentation/observation) (`@Observable`), not Combine/`ObservableObject`. Services (translation, import, network sending, certificates) all sit behind protocols and get injected into the view models, so they're testable without UI and without hitting the real network if needed.

```
lather/
  Models/       — SOAPRequest, Collection, SOAPResponse, RequestTimelineEntry, etc.
  Services/     — parsers (WSDL/Postman/Insomnia), XML<->JSON translator, HTTP sending,
                  syntax highlighting & validation (XML/JSON), certificates, VaultManager
  ViewModels/   — SidebarViewModel, WorkspaceViewModel
  Views/
    VaultSetupView.swift — first-launch/retry screen for choosing the vault
    Sidebar/    — collections/requests
    Workspace/  — request editor (3 layers), response, timeline, certificates
    Toolbar/    — Command Center
    Settings/   — vault location, placeholder for other global settings
  RootView.swift — switches between VaultSetupView and ContentView
```

## Known limitations

- **mTLS isn't implemented** — see the certificates section above.
- **The send timeline isn't persisted** — it lives in memory for the session only; collections and requests are (see Vault above), but the log of past sends resets when you quit.
- The JSON→XML translator always regenerates a standard `soapenv:` envelope — if you hand-edited the XML with a custom namespace or header content, those changes won't survive a later edit made from the JSON tab.
- The WSDL parser resolves types declared with `type=` (rpc/encoded style, like AFIP/ePagos). Doc/literal WSDLs that use `element=` on their `<part>`s aren't resolved yet (falls back to an empty placeholder).
