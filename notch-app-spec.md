# Build Prompt: macOS Dynamic Island for MacBook Pro

You are building a native macOS app that turns the MacBook Pro notch into an iOS-style Dynamic Island. Read this entire spec before writing code. Build in the phase order given at the bottom — do not jump ahead to features before the animation and window layer is solid.

App name placeholder: **Halo**. Rename freely.

---

## 0. Hard constraints

These are non-negotiable. If a suggested approach conflicts with one of these, the constraint wins.

1. **No Dock icon.** The app is an agent. `LSUIElement = true` in Info.plist, plus `NSApp.setActivationPolicy(.accessory)` at launch. The notch itself is the app's entire presence.
2. **Apple Music is the only music source.** Now Playing shows Apple Music (`com.apple.Music`) and nothing else, ever. No Spotify, no browser audio, no YouTube. If another app starts producing audio, the app's job is to silence it, not display it.
3. **The music library is local.** The user uploads his own files to Music.app; he does not have an Apple Music subscription. This means: no catalog features, no streaming lyrics, artwork is often missing, but **the actual audio files are on disk and readable** — which unlocks waveform and tempo analysis.
4. **Fluidity is the product.** If an animation looks like a resize instead of a morph, it is wrong. Motion quality outranks feature count. A janky app with 21 features is a failure; a glassy app with 5 is a success.
5. **No private frameworks except where this spec explicitly permits it**, and each such use must be wrapped in a availability check with a graceful fallback.

---

## 1. Stack and project setup

- **Swift 5.9+, SwiftUI** for all rendering, **AppKit** for the window layer.
- Minimum target: **macOS 14.4**. Several APIs below (Core Audio process objects, SwiftUI Metal shader effects) require it.
- **No App Sandbox.** This is a personal tool. Sandbox plus Apple Events plus Core Audio taps is a permissions nightmare with no payoff here. Enable Hardened Runtime only if distribution is ever wanted.
- Xcode project, not SPM executable — you need an app bundle for Info.plist keys and TCC permissions.
- No third-party dependencies unless a phase below explicitly calls for one.

### Info.plist keys required

```
LSUIElement                      = YES
NSAppleEventsUsageDescription    = "Halo reads what's playing in Music and can pause other audio apps."
NSMicrophoneUsageDescription     = "Halo shows which app is using your microphone."
NSCalendarsFullAccessUsageDescription = "Halo shows your next meeting in the notch."
```

Accessibility permission (`AXIsProcessTrustedWithOptions`) is needed for the volume/brightness HUD replacement. Prompt for it lazily, only when that feature is first enabled — never at launch.

---

## 2. The window layer

This is the foundation. Get it exactly right before anything else.

### The window

A borderless, non-activating `NSPanel` subclass:

```swift
final class NotchWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

`canBecomeMain` must stay false or the app will steal focus from whatever the user is typing in. Test this specifically: expand the island while typing in another app and confirm keystrokes keep landing there.

### Notch geometry

Do not hardcode notch dimensions. Compute them:

```swift
extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }
    var notchHeight: CGFloat { safeAreaInsets.top }          // ~32pt on 14"/16"
    var notchWidth: CGFloat {
        guard let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea else { return 0 }
        return frame.width - l.width - r.width
    }
}
```

`NSScreen` uses a bottom-left origin, so the notch sits at `frame.maxY`. Get this flip wrong and the window renders off-screen at the bottom — a common failure, check it first.

**Fallback:** on a Mac with no notch, or an external display, render a floating rounded pill centered at the top of the screen with the same dimensions the notch would have had. Every feature must work identically in this mode.

**Display changes:** observe `NSApplication.didChangeScreenParametersNotification` and rebuild the window. Users plug in monitors and close lids constantly; the app must survive it without leaving an orphaned window.

### Window sizing strategy

The window is always sized to the **largest** state the island can occupy, with a transparent background — do not resize the window during animation. Resizing an `NSWindow` per frame will never be smooth. Animate the SwiftUI content *inside* a fixed, oversized, transparent window. This single decision is the difference between iOS-smooth and obviously-a-Mac-app.

### Hover detection

Put an `NSTrackingArea` over a region slightly **taller and wider** than the idle notch, so the island begins reacting a few points before the cursor actually arrives. That anticipation is a large part of why the iOS version feels alive.

---

## 3. The animation system

Build this before any feature. Every feature is a view that gets handed to this system.

### States

Three, and only three:

| State | Trigger | Appearance |
|---|---|---|
| **Idle** | default | Exactly matches the physical notch. Invisible — indistinguishable from bare hardware. |
| **Compact** | music playing, or a transient event | Grows a few points wider than the notch. Album art peeks out the left, a live waveform out the right. The physical notch hides the middle, exactly like iOS. |
| **Expanded** | hover, or click | A full panel drops below the notch, corners flowing out of it. |

Transitions are always Idle ↔ Compact ↔ Expanded. Never skip a state — the intermediate frame is what sells the morph.

### Springs

Use SwiftUI's spring presets, tuned:

```swift
// state change (idle <-> compact)
.snappy(duration: 0.32, extraBounce: 0.14)
// expansion (compact <-> expanded)
.spring(response: 0.42, dampingFraction: 0.78)
// content settling inside a state
.smooth(duration: 0.25)
```

The slight overshoot from `extraBounce` is essential. A critically damped spring reads as "correct" and feels dead.

Drive every transition with an explicit `withAnimation { }` around a state mutation. Do not scatter `.animation(_:value:)` modifiers through the view tree — you will get compounding, conflicting curves that are impossible to debug.

### Morphing, not fading

Album art, text, and controls must **travel** between states using `matchedGeometryEffect` with a shared namespace. If album art fades out at 60x60 and fades in at 120x120, the illusion is dead. It must fly and scale along one continuous path.

### The goo (metaball) effect

This is what makes the island feel liquid rather than geometric. When a sub-element separates from the main pill — a notification bubble, the charging ripple — the two shapes should stretch and neck apart like mercury rather than cleanly detaching.

Technique — the alpha-threshold trick:

1. Render all island shapes as solid white into a single `Canvas` layer.
2. Apply `.blur(radius: 14)`. Overlapping shapes now bleed into each other with soft, low-alpha edges.
3. Apply a threshold on alpha: everything below ~0.5 alpha goes fully transparent, everything above goes fully opaque. The soft bleed snaps into a hard, connected surface.
4. Use that result as a mask for the actual island content.

In SwiftUI on macOS 14+, use `.layerEffect` with a small Metal shader for step 3. The shader is about ten lines: sample the layer, remap alpha with a smoothstep around the threshold, return. Fallback path if the shader fails to compile: `CIFilter` chain of `CIGaussianBlur` → `CIColorMatrix` with a large alpha multiplier → `CIColorClamp`.

Keep the blur radius and threshold as tunable constants at the top of the file. You will spend real time dialing these two numbers, and they matter more than almost anything else in the app.

### Corners

- All rounded rectangles use `style: .continuous` (squircles). Never the default circular radius — it is the single most obvious "this isn't Apple" tell.
- Where the expanded panel meets the notch, the top corners must curve **outward** (concave), so the panel appears to grow out of the notch rather than hang below it. This needs a custom `Shape` drawing quarter-arcs in the inverse direction. Do not skip this; it is the second most obvious tell.

### Performance

- Target 120Hz on ProMotion. Profile with the Core Animation instrument.
- Nothing in the island may drive animation from a `Timer`. Timers and springs fight; springs must own motion.
- The waveform and any audio-reactive element run on a display-synced update, and only while visible.
- Idle state must cost approximately zero CPU. Measure it: with nothing playing, the app should not appear in the top 50 of Activity Monitor.

---

## 4. Apple Music integration

### Do not use MediaRemote

`MRMediaRemoteGetNowPlayingInfo` and the rest of the private MediaRemote framework are what nearly every tutorial and every LLM will reach for. Apple restricted it to entitled processes in recent macOS versions and it will not work. Do not use it, do not try to work around it.

Use **ScriptingBridge into Music.app**. This is better for this project anyway: it is Apple-Music-only by construction, it is a public interface, and it exposes local file paths that MediaRemote never did.

### Setup

Generate the header once and commit it:

```
sdef /System/Applications/Music.app | sdp -fh --basename Music
```

Then `SBApplication(bundleIdentifier: "com.apple.Music")`.

**Critical:** sending any ScriptingBridge message to a non-running app **launches it**. Always guard:

```swift
var musicIsRunning: Bool {
    !NSWorkspace.shared.runningApplications
        .filter { $0.bundleIdentifier == "com.apple.Music" }.isEmpty
}
```

An app that launches Music.app every few seconds because a poll ran unguarded is a bug the user will notice within a minute.

### Events, not polling

Music.app broadcasts on the distributed notification center. Subscribe:

```swift
DistributedNotificationCenter.default().addObserver(
    forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main
) { note in ... }
```

The `userInfo` carries `Player State` (`Playing` / `Paused` / `Stopped`), `Name`, `Artist`, `Album`, `Total Time`, and `PersistentID`. This fires on every track change and play/pause with no polling and no launching.

Poll only one thing, and only while playing **and** the island is expanded: `playerPosition`, at about 5Hz, for the scrubber. Stop the poll the instant the island collapses or playback pauses.

### Fields to read

| Data | Property | Notes |
|---|---|---|
| Title / artist / album | `currentTrack.name` / `.artist` / `.album` | |
| Duration | `currentTrack.duration` | seconds |
| Position | `playerPosition` | read/write — writing seeks |
| Artwork | `currentTrack.artworks().first?.data` | **often empty for uploaded files** |
| **File on disk** | `currentTrack.location` | `NSURL`. This is what enables waveform + BPM. |
| Tempo tag | `currentTrack.bpm` | 0 if untagged — then compute it |
| Rating | `currentTrack.rating` | 0–100, 20-point steps = stars |
| Play count | `currentTrack.playedCount` | |

Controls: `playpause()`, `nextTrack()`, `previousTrack()`, `setPlayerPosition:`, `setSoundVolume:`.

---

## 5. The exclusivity engine

This is the feature the user cares most about and the one most likely to be built wrong. Read carefully.

**Goal:** Apple Music is the only thing making sound. If Spotify or a YouTube tab starts playing, it gets paused — and it never appears in Now Playing.

### Detection (macOS 14.4+)

Core Audio exposes process objects. Query `kAudioHardwarePropertyProcessObjectList` on `kAudioObjectSystemObject` to get an array of `AudioObjectID`s, then for each read:

- `kAudioProcessPropertyBundleID` — who it is
- `kAudioProcessPropertyIsRunningOutput` — is it currently making sound

Register a property listener on the process list so you react to changes instead of polling.

This gives you a live, reliable answer to "which apps are producing audio right now" with no private API.

### Enforcement

There is **no public per-process mute API on macOS.** Do not waste time looking for one; the answer is per-app levers:

| Offender | Lever |
|---|---|
| `com.spotify.client` | ScriptingBridge → `pause()`. Clean and instant. |
| Safari | AppleScript `do JavaScript "document.querySelectorAll('video,audio').forEach(e=>e.pause())"` across every tab of every window. |
| Chrome / Arc / Brave / Edge | Same `do JavaScript` approach — all Chromium browsers expose it. |
| Anything else | Post a `NX_KEYTYPE_PLAY` media-key `CGEvent`. Imprecise (it goes to whichever app holds media-key focus) but usually correct. |
| Still playing after both attempts | Give up gracefully. Show a card in the island: "Chrome is playing audio" with a button to bring it to the front. Never loop. |

**Browser caveat to surface in the app's settings UI:** the `do JavaScript` route requires the user to enable it once per browser — Safari: Develop → Allow JavaScript from Apple Events; Chrome: View → Developer → Allow JavaScript from Apple Events. Detect the failure and show a one-time explainer with those exact steps. Do not silently fail.

### Rules

- Debounce hard: wait ~400ms after detecting output before acting, so a notification chime or a UI click sound doesn't trigger an enforcement action.
- Maintain an **allowlist** in settings — system sounds, video calls, games, and anything the user adds should be exempt by default. Zoom being auto-paused mid-meeting would be a disaster.
- Two modes, user-selectable, defaulting to the first:
  1. **Enforce** — pause offenders (what the user asked for).
  2. **Display only** — never pause anything, just refuse to show non-Music sources in Now Playing.
- Never act during the first 5 seconds after login, while the audio graph settles.

---

## 6. Features

Each of these is a view plugged into the animation system from section 3. Build them in the phase order in section 8, not in this list order.

### Music

**F1 — Now Playing.** Compact state: album art on the left of the notch, live waveform bars on the right. Expanded: art, title, artist, scrubber, transport controls. Everything from section 4.

**F2 — Album-art color bleed.** Downsample artwork to 32×32, quantize to three dominant colors, pick the most saturated one that maintains contrast against black, and tint the island's glow and waveform with it. Cross-fade the tint over ~0.8s on track change. Cheap to build and the single highest-impact visual in the app.

**F3 — Artwork fallback generator.** Uploaded files frequently have no embedded art, so this fires constantly and must be built alongside F1, not after. When `artworks()` is empty, hash `artist + album` into a deterministic pair of hues and render a smooth gradient. Same album always produces the same gradient. Never show a gray music-note placeholder.

**F4 — Real waveform seek bar.** The files are local, so read them: `AVAudioFile` → decode → downsample to ~400 peak values → render as a `Shape` in the scrubber. The played portion is tinted with the F2 color, the remainder is dim. Analysis runs off the main thread on track change, cached to disk keyed by `PersistentID`. Streaming apps physically cannot do this — it is the app's signature feature. On decode failure, fall back to a plain bar.

**F5 — BPM-locked breathing.** Read `currentTrack.bpm` first; if it is 0, compute tempo with an onset-detection + autocorrelation pass over the first 30 seconds using vDSP, and cache it. Pulse the island's glow in time with the actual beat. Combined with F2 and F4 the notch becomes a small instrument panel.

**F6 — Audio-reactive waveform.** The compact-state bars respond to real output level, not a canned loop. Derive level from a Core Audio tap on Music's process. Smooth with an attack/release envelope (fast attack ~30ms, slow release ~200ms) so it breathes rather than strobes.

**F7 — Edge scrubbing.** Drag along the bottom edge of the island to scrub. Map x-position to `playerPosition`. **Expanded state only** — enabled in compact state, the user will scrub by accident every time they reach for the menu bar.

**F8 — Ratings and queue peek.** Set the local star rating from the island (`track.rating`, 20-point steps). Hover reveals the next three tracks from the current playlist.

**F9 — Sleep timer.** Stop playback in N minutes with a real volume fade-out over the last 20 seconds. Progress drains as an arc around the notch outline.

### System

**F10 — Volume and brightness HUD replacement.** Replace the gray macOS square with an island expansion.

The clean approach: install a `CGEventTap` on the media keys (`NX_KEYTYPE_SOUND_UP`, `SOUND_DOWN`, `MUTE`, `BRIGHTNESS_UP`, `BRIGHTNESS_DOWN`), **consume** the event, apply the change yourself, and render your own HUD. Because the system never sees the keypress, the stock HUD never appears — no need to fight `OSDUIHelper`, which respawns and is SIP-adjacent.

Volume: set `kAudioDevicePropertyVolumeScalar` on the default output device (public API, straightforward). Brightness: `DisplayServicesSetBrightness` is private — wrap it in a `dlopen`/`dlsym` lookup with a null check, and if it is unavailable, pass the brightness keys through to the system untouched and skip only that half of the feature.

Requires Accessibility permission. Put the whole feature behind a settings toggle and prompt only when enabled.

**F11 — Screenshot catcher.** Read the screenshot directory from `defaults read com.apple.screencapture location` (default `~/Desktop`), watch it with FSEvents, and slide new captures into the island as a thumbnail. Implement `NSDraggingSource` so the thumbnail can be dragged straight into Slack or Figma. Auto-dismiss after ~45s.

**F12 — Clipboard ring.** No pasteboard notification API exists, so poll `NSPasteboard.general.changeCount` every ~0.3s (cheap — it is an integer compare). Keep the last 10 entries, fan them out as cards on hover, click to restore. **Skip anything marked `org.nspasteboard.ConcealedType`** — that flag is how password managers say "do not store this."

**F13 — Scriptable live activities.** A localhost-only `NWListener` on a fixed port, plus a small `notch` CLI shim, so any script can push into the island:

```
notch push --id build --title "Building" --progress 0.4
notch push --id build --title "Done" --progress 1.0 --timeout 5
```

JSON body: `{id, title, subtitle, progress, symbol, timeout}`. Same `id` updates in place. **Bind to 127.0.0.1 only.** No paid notch app does this, and it makes the app genuinely yours.

**F14 — Charging ripple.** Observe power source changes via `IOPSNotificationCreateRunLoopSource`. On plug-in, expand with a ripple that flows outward from the connector side, then settle to a percentage and collapse. Half a day of work, disproportionate delight.

**F15 — Output device switcher.** Click to fan out available output devices; select to set `kAudioHardwarePropertyDefaultOutputDevice`. Fully public API, works cleanly.

**F16 — Mic and camera privacy indicator.** Mic is the easy and reliable half: use `kAudioProcessPropertyIsRunningInput` from the same process list as section 5 to show *which app* is listening. Camera detection is materially harder — attempt it via CoreMediaIO, and if it proves unreliable, ship mic-only rather than showing a wrong indicator.

**F17 — "Am I muted?"** When a call app holds the mic, show a live input level meter. **Be honest about what this measures:** it shows whether the mic is hot and whether sound is reaching it. It cannot read Zoom's internal mute state. In practice that is still the answer to the question — if you are talking and the bar is flat, you are muted.

**F18 — Downloads ring.** FSEvents on `~/Downloads`, watching for `.download`, `.crdownload`, and `.part`. True percentage requires a known total size, which is often unavailable — for Safari `.download` bundles you can read the expected size from the `Info.plist` inside. Where total size is unknown, show an indeterminate shimmer with a file count rather than a fake percentage.

**F19 — Focus arc.** A pomodoro that drains as a progress arc traced around the notch outline. No numbers, no panel — the notch itself is the timer.

**F20 — Meeting join.** EventKit (`requestFullAccessToEvents`). Two minutes before an event, expand with a Join button. Extract the conference URL from `event.url`, falling back to a regex over the notes for Zoom, Meet, and Teams links.

**F21 — Per-app volume mixer.** **Research task, not a v1 commitment.** macOS has no public per-app volume control. The only real routes are a virtual audio driver (a large project — an entire app in itself) or the coarse per-app levers from section 5. Build the *UI* listing which apps are producing audio, with pause and bring-to-front buttons, and label it accordingly. Do not let this expand into building an audio driver.

---

## 7. Settings and quitting

With no Dock icon and no menu bar item by default, there must still be a way out.

- **Right-click the island** → context menu with Settings, Pause enforcement, and Quit.
- A settings window as a normal `NSWindow` (this one *may* activate), with per-feature toggles, the offender allowlist, and the animation constants (blur radius, threshold, spring bounce) exposed as sliders so tuning does not require a rebuild.
- An optional, off-by-default menu bar item for users who want a visible escape hatch.
- Launch at login via `SMAppService.mainApp.register()`.

---

## 8. Build order

Do not reorder. Each phase must actually work before the next begins.

**Phase 1 — Skeleton.** Agent app, no Dock icon, notch window positioned correctly on the built-in display, correct geometry on external displays, survives sleep/wake and monitor changes. Render a plain colored rectangle over the notch. Ship nothing else until this is boring and reliable.

**Phase 2 — Motion.** The three states, springs, `matchedGeometryEffect`, continuous corners, concave top corners, the goo shader. Use placeholder content — colored circles are fine. **Spend real time here.** Tune the constants until it is indistinguishable from iOS. Everything downstream is easier if this is right, and nothing downstream can rescue it if it is wrong.

**Phase 3 — Music.** F1, F3, F2. ScriptingBridge, the distributed notification, artwork with the gradient fallback, color bleed. First genuinely useful build.

**Phase 4 — Exclusivity.** Section 5 in full. Detection, per-app levers, allowlist, debounce, the browser-permission explainer.

**Phase 5 — Signature features.** F4 waveform, F6 audio-reactive bars, F7 edge scrubbing, F5 BPM. This is where the app stops resembling anything purchasable.

**Phase 6 — System.** F10 HUD replacement, F11 screenshots, F14 charging, F15 device switcher.

**Phase 7 — The rest.** F8, F9, F12, F13, F16–F20. Independent of each other; build in whatever order appeals.

F21 stays research until everything above ships.

---

## 9. Do not do these

Explicitly out of scope. Each one looks tempting and each one is a dead end.

- **Do not use MediaRemote** for now-playing data. Restricted. Section 4 has the working approach.
- **Do not mirror macOS notifications** into the island. There is no public API. Every workaround is a private-framework hack that breaks on OS updates. Most paid notch apps quietly do not do this either.
- **Do not attempt Apple Music lyrics.** Not exposed to third parties, and the user does not want lyrics.
- **Do not resize the `NSWindow` during animation.** Fixed oversized transparent window, animate the content inside it.
- **Do not build a virtual audio driver** for F21 without an explicit decision to do so.
- **Do not let the app become main/key.** It must never steal focus.
- **Do not poll Music.app** for anything except `playerPosition`, and only while playing and expanded.
- **Do not ship circular corner radii.** `.continuous`, always.

---

## 10. Acceptance criteria

The app is done when all of these pass:

1. No Dock icon. No `⌘Tab` entry. Quitting is possible via the island's context menu.
2. In idle state the notch is visually indistinguishable from bare hardware, and the app uses effectively no CPU.
3. Playing a track in Music.app expands the island within one frame of the notification, showing correct art or a stable generated gradient.
4. Playing a YouTube video in Chrome pauses it within ~1 second, and it never appears in Now Playing.
5. Starting Spotify pauses it within ~1 second.
6. Joining a Zoom call does **not** get paused (allowlist works).
7. Expanding the island while typing in another app does not drop a single keystroke.
8. The waveform scrubber shows the real shape of the playing file, cached, with no hitch on track change.
9. Volume keys show the island HUD, and the gray system square never appears.
10. Plugging and unplugging an external monitor leaves exactly one correctly positioned island and no orphaned windows.
11. `notch push --id test --title "hi" --progress 0.5` renders in the island.
12. Every animated transition holds 120Hz on ProMotion under Core Animation profiling.

---

## 11. If something is blocked

If any API in this spec does not behave as described — Apple changes things, and parts of this were written against a moving target — **stop and report it rather than substituting a private framework or a hack.** State what failed, what you tried, and what the options are. A feature shipped as "not available on this OS version" is fine. A feature shipped on a private API that breaks in six months is not.
