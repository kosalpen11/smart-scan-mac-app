import LocalAuthentication

// MARK: - Touch ID / password

enum Auth {
    enum Outcome: Sendable {
        case success
        case cancelled
        case failed(String)
    }

    nonisolated static var hasTouchID: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            && context.biometryType == .touchID
    }

    /// Asks for Touch ID, falling back to the account password. `reason` completes
    /// "Clean Scheduler is trying to …".
    nonisolated static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .success : .failed("Authentication failed. Try again.")
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .passcodeNotSet:
                return .failed("Set a login password for this Mac, then try again.")
            default:
                return .failed("Authentication failed: \(error.localizedDescription)")
            }
        } catch {
            return .failed("Authentication failed: \(error.localizedDescription)")
        }
    }

    static var cleanButtonTitle: String { hasTouchID ? "Clean with Touch ID" : "Clean with Password" }
}
