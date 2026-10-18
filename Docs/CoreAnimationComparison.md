# Core Animation tab-transition trial

## Result

**No consistent motion-quality advantage demonstrated.** Ordinary transitions are equivalent. Brief intermediate-page flashes remain during rapid interruptions in both implementations. The candidate's vertical recording captured fewer same-run-loop burst flashes, but that improvement did not generalize to horizontal layout.

Keep `codex/core-animation-tab-transitions` for device comparison. It was created from `a9d6a25`; `codex/native-tab-transitions` remains unchanged. No merge is intended.

## Scope

Only `RootTabAnimator.swift` changes in production. Four direct `CABasicAnimation`s replace the two property animators inside the existing UIKit delegate. The fade remains 0.20 seconds, translation 0.30 seconds, travel 30 points, ease-out, without page scaling. The optional `interruptibleAnimator(using:)` implementation is removed.

The initial setup, model endpoints and cleanup disable implicit actions. Keys include a per-animator UUID; cleanup removes only owned keys. One weak `CATransaction` completion calls an idempotent cleanup path. Settlement requested before UIKit supplies the context still waits for that context. Normal transitions animate page views; only interrupted transitions use the existing snapshot handoff.

The controller, retained page hosts, Home state, outer navigation, glass menu, scanner lifecycle and sheet routing are unchanged. No dependency, production backend toggle, public API or deployment-target change was added.

## Measurements

Captured on Duo `08C1C642-7CD8-43F5-B174-D0B4B6047AC0`, iOS 27.1 Simulator. Both captures use the **actual system toolbar placement**: open portrait with the horizontal capsule, open landscape with the vertical rail. The active screen was display 3, respectively 2007 × 2853 and 2853 × 2007 pixels.

The opt-in test hosts the real Home, scanner, root controller and toolbar beneath a navigation stack. Each capture runs three repetitions of Home → Profile → Search → Scan → Home, rapid reversals, a same-run-loop selection burst, and mid-animation axis/Reduce Motion settlement. Axis and Reduce Motion settlement are injected at the controller boundary; the two overall layouts are actual Device Hub orientations.

| Capture | Ordinary transitions | Median fitted fade | Median fitted slide |
| --- | ---: | ---: | ---: |
| Baseline horizontal | 12 | 200.04 ms | 300.00 ms |
| Candidate horizontal | 12 | 200.00 ms | 299.99 ms |
| Baseline vertical | 12 | 200.01 ms | 300.00 ms |
| Candidate vertical | 12 | 200.00 ms | 300.00 ms |

All 48 ordinary transitions had the expected direction and 30-point travel, no orthogonal motion, no measured scaling, monotonic opacity/translation and stationary toolbar layout. Interrupted sequences ended on the expected tab with no active animator left behind.

Timing comes from fitting the standard ease-out curve to intermediate presentation-layer samples. Request-to-first-sample time includes SwiftUI/UIKit setup and display-link scheduling; it is not animation duration. Requested 60 ms rapid gaps were approximately 61–64 ms. Requested 40 ms gaps were actually 66–120 ms because main-thread selection/snapshot work and scheduling delayed continuation. Same-run-loop bursts exercise immediate selections independently of that limitation.

Display-link delivery was nonuniform: maximum intervals were 83.37/115.80 ms for baseline horizontal/vertical and 166.32/90.47 ms for the candidate. These are simulator callback observations, not rendered-frame, GPU or physical-device performance measurements. They establish no speed advantage.

## Frame inspection

Inspected consecutive captured frames around ordinary and interrupted changes in all three repetitions per layout and implementation. Ordinary fade/slide motion was visually equivalent, with fixed toolbar placement, no apparent scale and no uncovered full-frame flash.

| Captured symptom | Baseline horizontal | Candidate horizontal | Baseline vertical | Candidate vertical |
| --- | ---: | ---: | ---: | ---: |
| Rapid reversal briefly exposes an intermediate full page before the previous blend returns | 3/3 | 3/3 | 3/3 | 3/3 |
| Same-run-loop burst briefly exposes Scan before returning to the prior blend | 3/3 | 3/3 | 2/3 | 0/3 |

The vertical burst observation is a limited improvement in this capture, not an overall fix. The remaining flashes may involve native settlement and snapshot handoff; these recordings do not isolate the cause. This trial deliberately preserves that coordination policy.

Recordings have variable frame rate and duplicate or near-duplicate timestamps. Evidence frame IDs are more reliable than apparent frame duration. Trims preserve captured frames using passthrough output and a 1/600 encoder time base; exporting at average FPS dropped short flashes and was rejected. Launch fades, test-launch black frames, the diagnostic phase badge and the system “2 Views Open” banner are outside the tab-transition comparison.

## Validation

- Full Duo regression suite: **81 passed, 0 failed, 1 skipped**. The skipped test is the opt-in recording harness; it passed separately for all four captures.
- Lifecycle tests cover natural/early/pre-context completion exactly once, cancellation, external removal, owned-key cleanup, unrelated animation survival, old completion overlapping a newer transition, and animator release.
- The Home-retention integration test runs both animated and nonanimated variants. The animated variant verifies the native animator actually runs. All four host identities, Home's local state token, seven scroll views, Videos selection and 320-point scroll offset survive tab changes and a real quiz push/Back through the outer stack.
- Existing release-only selection, cancellation, RTL/vertical direction, accessibility, reduced motion, geometry settlement and deferred scanner-result tests pass.
- Generic iOS device build succeeded with `CODE_SIGNING_ALLOWED=NO`; deployment target remains iOS 26. No physical-device camera or material conclusion is claimed.
- The candidate is installed and running on Home in Duo's open-portrait layout. Final manual gesture/scanner/navigation checks were blocked by simulator tooling: input reported success without changing the visible display, and Device Hub returned an empty accessibility tree. Those behaviors are supported by the automated tests for this run, not a new successful manual interaction pass. The system's “2 Views Open” banner remained visible.

## Artifacts and reproduction

Recordings, frame evidence and metrics are saved outside Git at:

`/Users/francois/Desktop/swiftui/XStyle_TabBar-artifacts/core-animation-trial/`

The directory contains baseline/candidate recordings for both axes, `*-trial.mp4` trims, original raw recordings, the four presentation-sample JSON files, `comparison-metrics.json`, `comparison-metrics.txt`, frame-inspection notes, screenshots and build/test logs. Baseline recordings were completed while the production animator still exactly matched `a9d6a25`.

Run `RootTabMotionComparisonTests` alone with test-runner environment `TAB_COMPARISON_LABEL` set to a capture name and `TAB_COMPARISON_AXIS` set to `horizontal` or `vertical`. First place Duo in the corresponding orientation. The harness asserts the actual toolbar axis; it does not force a layout. Results are written to the app's `Documents/TransitionComparison` directory. The normal regression run skips this recording test.

Record the active screen with `simctl io <UDID> recordVideo --display=3`, stopping with SIGINT. The simulator may use different screen IDs after a posture/runtime change; verify the active display first. Extract the JSON through `simctl get_app_container <UDID> dev.kavsoft.XStyle-TabBar data`.

Compare the four JSON files with `python3 Scripts/analyze_tab_motion.py <baseline-horizontal.json> <candidate-horizontal.json> <baseline-vertical.json> <candidate-vertical.json>`; add `--format json` for per-transition estimates and timing brackets. Inspect recordings separately because the sampler does not include the outgoing interruption snapshot's pixels.

Final iPhone material appearance, Liquid Glass slider behavior, live-camera snapshot fidelity and subjective motion quality remain physical-device checks.

## Apple references

- [Custom transition animations](https://developer.apple.com/documentation/uikit/uiviewcontrolleranimatedtransitioning/animatetransition(using:)) supports either view animation or Core Animation inside the UIKit transition contract.
- [Transaction completion](https://developer.apple.com/documentation/quartzcore/catransaction/setcompletionblock(_:)) guarantees a main-thread callback after the group's animations finish or are removed.
