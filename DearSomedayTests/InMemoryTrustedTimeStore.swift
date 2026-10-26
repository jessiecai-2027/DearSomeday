//
//  InMemoryTrustedTimeStore.swift
//  DearSomedayTests
//
//  A `TrustedTimeStore` backed by a single in-memory property — no UserDefaults,
//  no disk. Test infrastructure only; lives in the test target so it never ships.
//
//  It is a faithful double: `lastSync` is just held and handed back, which is
//  exactly the contract `UserDefaultsTrustedTimeStore` implements (present ⇒ both
//  fields, nil ⇒ never synced). Constructing a fresh `TrustedClock` over a
//  *retained* instance of this store is how the tests simulate relaunch — the
//  anchor outlives the coordinator, just as UserDefaults outlives an app launch.
//

import Foundation
@testable import DearSomeday

final class InMemoryTrustedTimeStore: TrustedTimeStore {
    var lastSync: TrustedTimeSync?

    init(lastSync: TrustedTimeSync? = nil) {
        self.lastSync = lastSync
    }
}
