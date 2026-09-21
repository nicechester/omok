import Foundation
import FirebaseAuth
import FirebaseDatabase
import UIKit
import Observation

enum ConnectionStatus: Equatable {
    case connecting
    case connected
    case error(String)
}

@Observable
class AuthService {
    var currentUserID: String?
    var isAuthenticated: Bool { currentUserID != nil }
    @ObservationIgnored var connectionStatus: ConnectionStatus = .connecting

    /// Stable device-scoped identifier (IDFV). Used as the player UID in game seats.
    /// Falls back to a UUID stored in UserDefaults if IDFV is unavailable.
    let deviceUID: String = {
        let key = "omok.deviceUID"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let id = UIDevice.current.identifierForVendor?.uuidString
            ?? UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    private var authStateListener: AuthStateDidChangeListenerHandle?

    init() {
        setupAuthStateListener()
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    private func setupAuthStateListener() {
        // Eagerly set from cached user so currentUserID is non-nil before the
        // SwiftUI .task fires, preventing a redundant signInAnonymously() call.
        if let cached = Auth.auth().currentUser {
            currentUserID = cached.uid
            connectionStatus = .connected
        }
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUserID = user?.uid
            if user != nil {
                DispatchQueue.main.async {
                    self?.connectionStatus = .connected
                }
            }
        }
    }

    func signInAnonymously() async {
        // Reuse existing session if available (avoids creating a new UID on re-launch)
        if let existing = Auth.auth().currentUser {
            DispatchQueue.main.async {
                self.currentUserID = existing.uid
                self.connectionStatus = .connected
            }
            recordUIDMapping(firebaseUID: existing.uid)
            return
        }
        connectionStatus = .connecting
        do {
            let result = try await Auth.auth().signInAnonymously()
            DispatchQueue.main.async {
                self.currentUserID = result.user.uid
                self.connectionStatus = .connected
            }
            recordUIDMapping(firebaseUID: result.user.uid)
        } catch {
            DispatchQueue.main.async {
                self.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    private func recordUIDMapping(firebaseUID: String) {
        guard firebaseUID != deviceUID else { return }
        let ref = Database.database().reference()
            .child("omok/uidMappings").child(deviceUID).child("firebaseUids")
        Task {
            guard let snapshot = try? await ref.getData() else { return }
            var existing: [String] = (snapshot.value as? [String]) ?? []
            guard !existing.contains(firebaseUID) else { return }
            existing.append(firebaseUID)
            try? await ref.setValue(existing)
        }
    }
}
