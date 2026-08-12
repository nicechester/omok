import Foundation
import FirebaseAuth
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
        connectionStatus = .connecting
        do {
            let result = try await Auth.auth().signInAnonymously()
            DispatchQueue.main.async {
                self.currentUserID = result.user.uid
                self.connectionStatus = .connected
            }
        } catch {
            DispatchQueue.main.async {
                self.connectionStatus = .error(error.localizedDescription)
            }
        }
    }
}
