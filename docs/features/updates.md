# Updates

Noto updates itself through [Sparkle](https://sparkle-project.org). `Noto/Features/Updates/` holds one
file, `UpdateCoordinator`: the owner of Sparkle's `SPUStandardUpdaterController`, and the action
surface that the menu bar item, the app menu and the General pane call.

`AppCore.start()` calls `UpdateCoordinator.start()` after the hotkeys. The build side (the feed, the
signatures, the workflow) is in [release.md](../release.md).

## Invariants

- `SUPublicEDKey` in `Noto/Info.plist` pairs with the `SPARKLE_ED_PRIVATE_KEY` secret in
  noto-releases. An installed Noto rejects a feed signed with any other key, so neither changes alone.
- `SUFeedURL` is the latest release's `appcast.xml` on noto-releases. Each release replaces the feed.
- Sparkle compares `CFBundleVersion` (`CURRENT_PROJECT_VERSION`). Each release carries a larger number
  than the one before. The version rule in release.md keeps it equal to the tag.
- Check for updates automatically is Sparkle's own `SUEnableAutomaticChecks` default, under the
  bundle id like every preference. `Info.plist` sets it on, so Sparkle never asks for permission at the
  second launch. It is not a `NotoSettings` key; `UpdateCoordinator.checksAutomatically` mirrors it.
- Scheduled reminders are gentle. `UpdateCoordinator` is the `SPUStandardUserDriverDelegate` and
  declares `supportsGentleScheduledUpdateReminders`, so an update a scheduled check finds never steals
  focus. Sparkle shows its window behind the active app, and the menu bar item's Check for Updates…
  reads Update to <version>… until the user looks at it. A user-initiated check shows at once.
- A Debug build runs the same updater against the same feed, because it shares the bundle id.

## Dispatch

- Check for Updates… in the menu bar item, Check for Updates… after About in the app menu, and Check
  Now in Settings > General call `UpdateCoordinator.checkForUpdates()`. Sparkle starts a check, or
  brings the update already on screen to the front.
- `canCheckForUpdates` mirrors Sparkle's KVO property of the same name and disables those three
  controls while a check is on screen. The KVO closure is `Sendable`, so the write hops back to the
  main actor in a `Task`.
- `pendingVersion` is set in `standardUserDriverWillHandleShowingUpdate` for a scheduled check, and
  cleared in `standardUserDriverDidReceiveUserAttention` and `standardUserDriverWillFinishUpdateSession`.
- Sparkle's windows are not reported to `ActivationPolicy`. With Show in Dock off, the update alert
  shows without a Dock icon, which is enough to click Install Update.

## Verification

No harness covers this folder. The Settings section of the manual sweep in
[testing.md](../testing.md#settings) covers Check Now and the automatic check.
