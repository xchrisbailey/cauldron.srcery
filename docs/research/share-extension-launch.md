# Share-extension app launching on iPhone and Mac

Research for [Establish supported share-extension app launching on iPhone and Mac](https://github.com/xchrisbailey/cauldron.srcery/issues/213), under [Share-sheet editing and immediate Cauldron handoff](https://github.com/xchrisbailey/cauldron.srcery/issues/212).

Investigated 2026-10-20 against Apple documentation, Apple staff guidance, local Xcode 27.0 (27A266a) SDK headers for iOS/macOS 27.0, and repository commit `e064a87`. This report establishes constraints; it does not choose product fallbacks or change the app.

## Findings

| Platform | Supported API evidence | Consequence |
| --- | --- | --- |
| iPhone share extension | `NSExtensionContext.open` support depends on the extension point; Apple's current reference lists Today and iMessage on iOS, excluding Share. Apple staff explicitly says direct containing-app launch from Share is unsupported. | An explicit Edit click does not grant the extension a supported immediate launch path. Do not promise automatic opening on iPhone under the documented APIs. |
| Mac share extension | Public AppKit `NSWorkspace` URL/application opening APIs and `shared` have no extension-unavailable annotation in the installed SDK. They support activation, launch, and reuse of a running application. | There is a credible public API path on Mac. Its behavior in Cauldron's signed share-extension sandbox and host popover still needs validation. Do not generalize the iOS restriction to Mac or claim successful delivery from declarations alone. |

Sources: [current NSExtensionContext.open reference](https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:)?changes=_2%2C_2), [Apple DTS guidance on iOS Share](https://developer.apple.com/forums/thread/764570), [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace), and the SDK declarations recorded below.

## iPhone: dispatch permission and URL routing are different

The current `NSExtensionContext.open` reference makes availability conditional on the extension point; being able to compile a call does not establish that a Share extension may dispatch it. The reference's completion boolean reports success or failure. The older [App Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html) mentions only Today; use the current reference's Today/iMessage list rather than treating that archived list as exhaustive for modern iOS.

In [iOS 18 ShareExtension openURL](https://developer.apple.com/forums/thread/764570), Apple DTS explains that bypassing the unavailable `UIApplication` object through the Objective-C runtime is unsupported, and later answers that opening the main app from Share is unavailable. A [January 2025 Frameworks Engineer answer](https://developer.apple.com/forums/thread/773342) independently states that direct launch is unsupported with the available extension APIs and invites an enhancement request. These discussions concern iOS/UIKit; their broad wording is not proof that public macOS AppKit APIs are unavailable.

The local iPhoneOS 27.0 `UIKit.framework/Headers/UIApplication.h` marks `sharedApplication` with `NS_EXTENSION_UNAVAILABLE_IOS`. `Foundation.framework/Headers/NSExtensionContext.h` declares `openURL:completionHandler:` without an extension-specific compile-time ban, consistent with support being decided at runtime by the extension point. There is no supported cold-launch versus warm-activation exception documented for Share. A running containing app does not itself give the extension permission to foreground it.

Registering `cauldron` in `CFBundleURLTypes` only prepares Cauldron to receive links from an allowed sender. It does not authorize the share extension to send them. Switching a link to a universal link, invoking SwiftUI's URL environment action, or using an App Intent does not establish a new permission: no primary source found documents those as a general Share-to-containing-app launch contract. Responder-chain tricks, private Launch Services interfaces, JavaScript navigation tricks and disabling extension-safe API checks are outside this investigation.

## Mac: public NSWorkspace path, with remaining validation

The installed macOS 27.0 `AppKit.framework/Headers/NSWorkspace.h` declares `sharedWorkspace`, `openURL:`, asynchronous `openURL:configuration:completionHandler:`, `openURLs:withApplicationAtURL:configuration:completionHandler:`, and `openApplicationAtURL:configuration:completionHandler:` without an extension-unavailable annotation. The async APIs are available since macOS 10.15. This is a material difference from iOS's unavailable singleton.

[NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace) publicly documents both URL dispatch and app launching. The synchronous [open URL method](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)) reports a boolean. The async methods report a running application or error; their SDK comments specify a concurrent completion queue. `NSWorkspace.OpenConfiguration` has these documented SDK defaults:

- `activates = true`: bring the app to the foreground.
- `createsNewApplicationInstance = false`: prefer an existing instance.
- `allowsRunningApplicationSubstitution = true`: an already-running copy at another URL may substitute.
- `promptsUserIfNeeded = true`: system UI may delay completion; Gatekeeper UI is independent.
- Command-line `arguments` are ignored when the caller is sandboxed.

These define cold launch and warm reuse behavior for the workspace request, not successful presentation of a particular Cauldron editor. Opening the containing application alone carries no specific draft route. The API that opens URLs in a specified app can combine a route with an explicit target application, avoiding reliance only on the default custom-scheme handler; how to identify the containing installation and handle multiple installed copies remains an implementation decision.

Sandboxing alone is not evidence that NSWorkspace cannot launch an app: [Apple DTS recommends NSWorkspace for launching a sandboxed application](https://developer.apple.com/forums/thread/747499), distinguishing it from spawning it as an inheriting child process. That guidance is about macOS app launching generally, not a signed Cauldron share-extension guarantee. No reviewed source expressly certifies the exact Share popover / sandbox / foreground transition. Treat this as a public API candidate requiring a signed integration check, not proven impossible and not already verified.

## Persistence, completion and failure

The [extension lifecycle guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html) says the system terminates an extension shortly after its task. In both SDKs, `NSExtensionContext.h` describes `completeRequestReturningItems:completionHandler:` as eventually dismissing the extension view; its optional post-completion work runs at background priority and can expire. Therefore an implementation must not rely on arbitrary delayed work after completion to persist or launch.

Engineering inference: persist the complete handoff payload before requesting an allowed opening. On Mac, request opening while the extension is alive, handle the result, and only then complete the extension request if appropriate. A successful workspace open still does not acknowledge that the app consumed a specific payload; preserve it until the receiver's consumption policy permits deletion. Completion alone returns to the host and is not a launch signal.

For unsupported iOS dispatch or failed Mac opening, the supported existing transport is the shared App Group container; Apple documents shared containers for extension/containing-app data in the lifecycle guide. A containing app can receive it when the user next opens the app. Inline editing/saving can avoid needing foreground launch for those tasks. These are available facts, not a selection of Chris's fallback UX.

Apple DTS's notification suggestion in [the iOS thread](https://developer.apple.com/forums/thread/764570) was clarified as the containing app posting a notification and the user tapping it. It is not evidence that an otherwise dormant app can be awakened by the Share extension to schedule one, nor that Share has permission to post on its behalf. Notifications are not established here as a drop-in handoff solution.

## Distribution constraints

[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) require public APIs used for their intended purposes (2.5.1), extension guideline compliance (4.4), sandboxing for Mac App Store apps (2.4.5), and guideline compliance for TestFlight betas (2.2). An explicit user click is relevant intent but does not override extension restrictions. Public declarations and successful local testing cannot guarantee App Review approval; the research found no special entitlement granting iOS Share direct launch.

## Cauldron's present integration gaps

At `e064a87`, `ShareSheetModel.sendToCauldron()` writes only the original `SharedItem` to `ShareInbox`, discards the parsed import and then closes. `ShareViewController` completes the extension request without requesting opening. Its comment that an extension cannot open its app is too broad for the macOS API evidence.

`Cauldron-Info.plist` already registers the `cauldron` scheme. `AppLink` recognizes only `cauldron://tracker/today`, and `AppShell.onOpenURL` handles recognized links. There is no draft-specific route. `docs/native/imports.md` describes original link/text pickup at launch/foreground and a Mac watcher for finished recipes only. Thus launch API feasibility does not solve preserving inline edits, exact-draft routing, queue order or consumption acknowledgement. Those remain separate decisions.

## Validation still needed

No launch attempt, compile probe, host UI run or signed-device test was performed. This is source research only.

1. Compile the eventual Mac bridge with extension-safe API checks enabled; test the signed sandboxed extension from Safari and other real hosts.
2. Test Mac cold launch, background app, already-frontmost app, closed windows, existing editor/import sheet, and multiple installations. Observe focus, URL delivery, popover dismissal and workspace error/completion timing.
3. Verify persistence-before-open and recovery from failed opening, extension termination and repeated URL delivery. A draft must not disappear or be duplicated because URL opening succeeded.
4. Verify iPhone's selected supported fallback and inline fields on a real device. A simulator observation that an unsupported launch trick works would not establish a supported distribution contract.
5. If immediate iPhone opening remains mandatory, request authoritative Apple clarification or enhancement rather than treating workaround anecdotes as an implementation contract.

SDK evidence is reproducible locally under `/Applications/Xcode.app/Contents/Developer/Platforms/{iPhoneOS,MacOSX}.platform/Developer/SDKs/{iPhoneOS,MacOSX}.sdk/System/Library/Frameworks/`, in `Foundation.framework/Headers/NSExtensionContext.h`, `UIKit.framework/Headers/UIApplication.h` (iOS), and `AppKit.framework/Headers/NSWorkspace.h` (Mac). These installed Apple SDK declarations supplement the linked primary documentation; no third-party SDK mirror was used.
