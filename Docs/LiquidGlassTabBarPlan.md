# Netflix-inspired glass menu and native tab transitions

## Architecture — option 2

Use an app-owned `UITabBarController`, bridged with `UIViewControllerRepresentable`, in place of the hidden SwiftUI `TabView`. Retain one typed `UIHostingController` for each root tab. UIKit owns tab containment and appearance; updating a host's root value must preserve its SwiftUI identity, local state, and actual scroll views. Do not keep all pages mounted in a SwiftUI `ZStack` and do not take over SwiftUI's private tab controller.

Keep the existing outer `NavigationStack` and system-managed toolbar. A shared navigation model routes article and quiz actions across hosting boundaries into the same outer path; Back, interactive pop, sidebar routes and article zoom sources remain part of that navigation. Forward explicit public environment values to the existing hosts, preserving each host's local layout and presentation environment. Carry the outer toolbar's safe-area insets into UIKit without reducing Home's full-width paging viewport. The toolbar remains outside the page animation container and follows Duo's system-provided vertical edge.

## Glass and input

- Keep `UIGlassContainerEffect` and `.regular UIGlassEffect`, with 25% black tint in dark appearance and unset tint in light appearance.
- Use 28-point symbols (up to 34 with scaling), 10-point caption-scaled labels, at least 44-point touch targets and a 64-point horizontal minimum height. Use the vertical icon-only representation in Duo's rail.
- Track a finger immediately and move a temporary highlight continuously; the page and camera selection change only on release inside the menu. Releasing outside cancels. Re-entering resumes tracking. Releasing on the current tab does not switch pages.
- Expand the capsule by up to 4% while held and rebound over about 0.35 seconds. Disable native interactive-glass deformation to avoid duplicating this motion.
- Preserve committed accessibility selection during tracking. Cancel for real geometry, axis, direction, enabled-state or external selection changes, not repeated same-value updates.

## Page motion

Implement `UITabBarControllerDelegate.tabBarController(_:animationControllerForTransitionFrom:to:)` with `UIViewControllerAnimatedTransitioning`. On release, fade for 0.20 seconds and translate for 0.30 seconds using ease-out timing. Incoming content starts 30 points toward the destination; outgoing content travels 30 points in the opposite direction. Do not scale content. Use visible order for RTL and up/down for the vertical menu.

Keep a continuous background and clip to the content viewport. Settle immediately for layout-axis changes and Reduce Motion. During rapid retargeting, finish the previous UIKit transition before starting another, using only a temporary snapshot of its current displayed composite to maintain visual continuity; never queue a stale selection. Normal transitions animate the actual page views. Camera-layer snapshot fidelity remains a physical-device check.

Only committed content receives interaction and accessibility. Camera activity depends on committed Scan selection, root visibility and scene activity. Preserve asynchronous scanner results while inactive and present them on returning to Scan.

## Validation

- Build `XStyle_TabBar` for a generic iOS device with signing disabled and retain iOS 26 deployment support.
- Run targeted tests on Duo `08C1C642-7CD8-43F5-B174-D0B4B6047AC0`: native animator invocation, forward/reverse and skipped-tab direction, rapid interruptions, axis settling, Reduce Motion, touch cancellation, and deferred scan results.
- Verify actual Home scroll-view identity, category selection, offsets and local state across switches and navigation pushes/Back.
- Exercise the Duo simulator in horizontal and vertical toolbar layouts: all tabs, hold without preview, drag/release, sheets, scanner controls, article and quiz navigation, rotation/folding, and duplicate-bar/inset regressions.
- Leave final physical-device translucency, Liquid Glass slider extremes, and live-camera fidelity to the user.

## Implementation validation — 19 October 2026

- Generic iOS device build succeeded with signing disabled; the deployment target remains iOS 26.
- All 74 tests passed on the requested Duo. The controller suite also passed after removing its compiler warning, and the retention integration test passed with the real `QuizDestination` pushed and popped through the outer stack.
- Home retained its local state, category, exact scroll offsets and seven underlying scroll views across all root tabs and navigation. Folding and safe-area regression tests passed without relaxing their assertions.
- Simulator inspection verified the closed vertical rail, open landscape rail and open portrait capsule, including a fresh launch with content clear of the rail. Hold without preview, final-candidate release, outside cancellation, article push/Back and a simulated scan result were exercised.
- Automated coverage includes RTL, accessibility activation, text-size/axis changes, reduced motion, interrupted selections, discarded snapshots, animator release and deferred scanner sheets.
- Manual quiz interaction and a new frame-by-frame recording were not completed because simulator input tools became unreliable after posture changes. Quiz push/Back is covered by the integration test; final reference-motion comparison, material appearance and live-camera checks remain device validation.

## Apple references

- [Tab controller transition delegate](https://developer.apple.com/documentation/uikit/uitabbarcontrollerdelegate/tabbarcontroller(_:animationcontrollerfortransitionfrom:to:))
- [UIHostingController](https://developer.apple.com/documentation/swiftui/uihostingcontroller)
- [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/)

## Core Animation trial — 19 October 2026

The experimental branch `codex/core-animation-tab-transitions` starts at `a9d6a25`. Keep `codex/native-tab-transitions` at that commit and do not merge the experiment automatically.

- Limit production changes to `RootTabAnimator`. Preserve the native tab delegate, retained hosts, navigation stack, glass toolbar, camera gating, and existing interruption/snapshot policy.
- Start four explicit `CABasicAnimation`s from `animateTransition(using:)`: incoming/outgoing translation for 0.30 seconds and opacity for 0.20 seconds, all ease-out. Preserve 30-point travel, RTL, vertical motion and unscaled content. Remove the optional property-animator method.
- Set model endpoints with implicit actions disabled. Give every transition unique keys and remove only its own animations. Complete UIKit exactly once through guarded cleanup, including cancellation, early removal and settlement before the context arrives. Use a weak transaction completion so delayed callbacks cannot retain the animator or alter a newer transition.
- Capture the original implementation before replacing it. Run the same opt-in harness for three repetitions on each implementation and actual Duo toolbar axis, recording the active display and sampling presentation layers. Include nominal 450 ms ordinary changes, 60/40 ms rapid changes, same-run-loop bursts, axis changes and Reduce Motion changes.
- Add lifecycle regression coverage and an animated Home-retention integration variant. Build for a generic iOS device without signing; retain iOS 26 support.

Completed: four captures, frame inspection, 81 passing regression tests, four targeted recording-test passes, and the unsigned device build. Ordinary timing is equivalent. Rapid-interruption page flashes remain in both implementations; a reduction in vertical burst flashes did not repeat horizontally, so no consistent motion-quality advantage is established. Keep the candidate available for physical-device comparison. See [the comparison report](CoreAnimationComparison.md) for recordings, measurements, limitations and reproduction steps.
