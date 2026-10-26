//
//  TrustedTime.swift
//  DearSomeday
//
//  The clock used by the postcard lock lifecycle. Production reads the device
//  wall clock when the app launches or returns to the foreground, then advances
//  that local anchor with monotonic uptime while the app remains active.
//
//  This is intentionally a convenience lock, not a security boundary. Changing
//  the device date can change when a postcard unlocks. Using device time keeps
//  the app offline-capable and avoids sending a network request merely to learn
//  the current time.
//
//  ── The mechanism (§5.4) ───────────────────────────────────────────────────
//
//    At sync:   lastTrustedTime = deviceNow
//               uptimeAtSync    = systemUptime               (monotonic anchor)
//
//    Evaluate:  trustedNow = lastTrustedTime + (systemUptime − uptimeAtSync)
//
//  `systemUptime` (ProcessInfo.processInfo.systemUptime) is monotonic and NOT
//  user-settable — it only ever counts up while the device is awake, and it
//  resets to ~0 on reboot. So the delta since the last sync is a lower bound on
//  elapsed time without repeatedly reading the wall clock.
//
//  ── Why the pieces are shaped the way they are ─────────────────────────────
//
//  • The calculation is PURE (`TrustedTimeCalculator`, free functions over
//    values). Both runtime inputs — the wall-clock instant and the uptime
//    reading — are injected, never read from the environment inside the math.
//    Tests can't reboot a device to reset `systemUptime`, so the only way to
//    exercise the reboot path is to hand the logic a smaller uptime than the
//    one it synced at. Injection is what makes "offline reboot" (§9) testable
//    at all.
//
//  • Two outcomes remain (`TrustedTime`): `.trusted(Date)` or `.neverSynced`.
//    Production refreshes immediately from device time; `.neverSynced` remains
//    useful for deterministic tests and for safe initialization ordering.
//
//  ── Proportionality (§5.4) ─────────────────────────────────────────────────
//  "The person being locked out asked to be locked out." This is a diary lock,
//  not adversarial security. The app deliberately accepts device-time changes.
//

import Foundation

// MARK: - Outcome

/// The result of asking the trusted-time layer for the current instant.
///
/// Exhaustively two cases — see the file header. Callers in the lock lifecycle
/// switch on this: `.neverSynced` means the source has not been sampled yet.
enum TrustedTime: Equatable {
    /// A locally anchored instant, projected forward by monotonic uptime and
    /// clamped so it never precedes the last synced instant.
    case trusted(Date)

    /// The injected time source has not produced an instant yet.
    case neverSynced
}

// MARK: - Persisted anchor

/// The `(lastTrustedTime, uptimeAtSync)` pair captured at a sync. Persisted so
/// projected time survives relaunch until the device clock is refreshed.
///
/// The two fields are meaningful ONLY together — `uptimeAtSync` is the uptime
/// reading *at the moment* `lastTrustedTime` was authoritative. They must be
/// written and read as a unit; a mismatched pair would project a garbage
/// instant. That coupling is why this is one value, not two loose settings.
struct TrustedTimeSync: Equatable {
    /// The device-clock instant from the last refresh.
    let lastTrustedTime: Date

    /// `systemUptime` sampled at that same moment. The monotonic anchor.
    let uptimeAtSync: TimeInterval
}

// MARK: - Pure calculation

/// The §5.4 arithmetic, as pure functions over injected values. No stored
/// state, no environment reads, no `Date()`, no `ProcessInfo`. This is the part
/// the tampering/offline-reboot tests (§9) drive directly.
enum TrustedTimeCalculator {

    /// True if `currentUptime` is *less* than the uptime we synced at, which can
    /// only happen if the device rebooted since the sync (uptime resets to ~0 on
    /// reboot and otherwise only increases). Detected explicitly rather than
    /// folded silently into the projection so the reboot case is nameable — it's
    /// the exact situation §5.4 calls out ("reboots offline… stays locked").
    nonisolated static func rebooted(
        uptimeAtSync: TimeInterval,
        currentUptime: TimeInterval
    ) -> Bool {
        currentUptime < uptimeAtSync
    }

    /// Projects the synced instant forward to now: `lastTrustedTime + (uptime −
    /// uptimeAtSync)`, **clamped so the result never precedes `lastTrustedTime`**.
    ///
    /// A reboot makes the delta negative (`rebooted(...)` is true). We do NOT
    /// treat that as an error or throw it away — the cached sync is still a valid
    /// *lower bound* on the real time: whatever the true instant is, it's at
    /// least `lastTrustedTime`, since that instant genuinely happened. So we
    /// return `lastTrustedTime` unchanged. For a locked card whose unlock date is
    /// still in the future, that keeps it locked (the projection hasn't reached
    /// it) — exactly the §5.4 "reboots offline, stays locked" behaviour. A
    /// non-positive delta from a same-instant read clamps identically and
    /// harmlessly.
    nonisolated static func project(
        _ sync: TrustedTimeSync,
        currentUptime: TimeInterval
    ) -> Date {
        let delta = currentUptime - sync.uptimeAtSync
        guard delta > 0 else { return sync.lastTrustedTime }
        return sync.lastTrustedTime.addingTimeInterval(delta)
    }
}

// MARK: - Persistence seam

/// Where the `TrustedTimeSync` anchor lives across launches. A seam, mirroring
/// the `PostcardStore` pattern: production persists to `UserDefaults`, tests use
/// an in-memory double, and neither the calculation nor the coordinator care
/// which. `nil` means "never synced".
///
/// A class (reference) protocol on purpose: `TrustedClock` holds one and writes
/// through it; value semantics would silently drop persisted writes.
protocol TrustedTimeStore: AnyObject {
    /// The last persisted anchor, or `nil` if none has ever been written.
    /// Setting `nil` clears it (e.g. a future "forget synced time" path).
    var lastSync: TrustedTimeSync? { get set }
}

/// The production `TrustedTimeStore`: a couple of `UserDefaults` keys. Tiny,
/// non-secret data — this is a diary lock (§5.4 proportionality), so there's no
/// call for the Keychain or attestation here.
// `nonisolated`: this type only shuttles values in and out of the thread-safe
// `UserDefaults`, touches no main-actor state, and is constructed as
// `TrustedClock.init`'s default argument (evaluated in a nonisolated context).
// Opting the whole type out of the module's default MainActor isolation keeps
// that construction warning-free without scattering `nonisolated` per member.
nonisolated final class UserDefaultsTrustedTimeStore: TrustedTimeStore {

    private enum Key {
        static let lastTrustedTime = "trustedTime.lastTrustedTime"
        static let uptimeAtSync = "trustedTime.uptimeAtSync"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastSync: TrustedTimeSync? {
        get {
            // Presence is gated on the Date object: `object(forKey:)` is nil when
            // absent, whereas `double(forKey:)` returns 0.0 for a missing key and
            // couldn't be told apart from a genuine zero uptime. Both fields are
            // written and cleared together, so the Date's presence implies the
            // Double's.
            guard let last = defaults.object(forKey: Key.lastTrustedTime) as? Date else {
                return nil
            }
            let uptime = defaults.double(forKey: Key.uptimeAtSync)
            return TrustedTimeSync(lastTrustedTime: last, uptimeAtSync: uptime)
        }
        set {
            guard let sync = newValue else {
                defaults.removeObject(forKey: Key.lastTrustedTime)
                defaults.removeObject(forKey: Key.uptimeAtSync)
                return
            }
            defaults.set(sync.lastTrustedTime, forKey: Key.lastTrustedTime)
            defaults.set(sync.uptimeAtSync, forKey: Key.uptimeAtSync)
        }
    }
}

// MARK: - Coordinator

/// Ties the pure calculation to its injected runtime source and its persisted
/// anchor. This is what the rest of the app talks to: `now()` to read projected
/// time and `refresh()` when the app launches or returns to the foreground.
///
/// The only injected runtime input is `uptime` — the monotonic clock.
/// Production wires `{ ProcessInfo.processInfo.systemUptime }`; a test hands
/// back a value it controls, and *lowering* it between calls is how a test
/// simulates the reboot it can't actually perform.
///
/// Production injects `DeviceTimeSource`; tests inject fixed values so lifecycle
/// behavior remains deterministic without changing the system clock.
@MainActor
final class TrustedClock {

    private let store: TrustedTimeStore
    private let uptime: () -> TimeInterval
    private let source: TimeSource

    /// - Parameters:
    ///   - store: where the anchor persists. Defaults to `UserDefaults`.
    ///   - uptime: reads the monotonic system uptime. **No default** — the
    ///     caller states the source explicitly so the injection seam is never
    ///     bypassed by accident.
    ///   - source: the wall-clock source used by `refresh()`. Production uses
    ///     device time; tests may inject a fixed source.
    init(
        store: TrustedTimeStore = UserDefaultsTrustedTimeStore(),
        uptime: @escaping () -> TimeInterval,
        source: TimeSource = DeviceTimeSource()
    ) {
        self.store = store
        self.uptime = uptime
        self.source = source
    }

    /// The current projected instant, or `.neverSynced` before the source has
    /// been sampled.
    func now() -> TrustedTime {
        guard let sync = store.lastSync else { return .neverSynced }
        return .trusted(TrustedTimeCalculator.project(sync, currentUptime: uptime()))
    }

    /// Records a freshly sampled wall-clock instant, persisting a new anchor.
    ///
    /// **Monotonic guard:** `lastTrustedTime` is never overwritten with an
    /// earlier value. If `serverNow` predates the stored anchor's
    /// `lastTrustedTime` (a stale/replayed/skewed response), the whole pair is
    /// left intact — bumping `uptimeAtSync` while keeping the old, later instant
    /// would rewind the next projection, so the anchor moves as a unit or not at
    /// all. Trusted time thus advances or holds, never regresses across syncs.
    ///
    /// - Returns: trusted time as of immediately after the sync, for callers
    ///   that want to re-evaluate a lock right away.
    @discardableResult
    func sync(serverNow: Date) -> TrustedTime {
        if let existing = store.lastSync, serverNow < existing.lastTrustedTime {
            // Reject the regression; keep the existing (still-valid) anchor.
            return .trusted(TrustedTimeCalculator.project(existing, currentUptime: uptime()))
        }
        // Sample uptime once so the persisted anchor and the returned projection
        // are computed against the very same reading.
        let sampledUptime = uptime()
        let fresh = TrustedTimeSync(lastTrustedTime: serverNow, uptimeAtSync: sampledUptime)
        store.lastSync = fresh
        return .trusted(TrustedTimeCalculator.project(fresh, currentUptime: sampledUptime))
    }

    /// Refreshes the local anchor from the injected wall-clock source.
    /// Production's device-time source returns immediately and performs no I/O.
    @discardableResult
    func refresh() async -> TrustedTime {
        guard let sourceNow = await source.currentInstant() else {
            return now()
        }
        return sync(serverNow: sourceNow)
    }
}

// MARK: - Wall-clock source

/// Injectable so tests can supply deterministic time without changing the
/// device clock.
protocol TimeSource {
    func currentInstant() async -> Date?
}

/// Production source: the date and time configured on the device.
nonisolated struct DeviceTimeSource: TimeSource {
    func currentInstant() async -> Date? {
        Date()
    }
}
