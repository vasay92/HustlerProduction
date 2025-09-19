

import FirebaseFirestore

protocol ListenerManageable {
    var listeners: [ListenerRegistration?] { get set }
    func setupListeners()
    func cleanupListeners()
}

extension ListenerManageable {
    mutating func cleanupListeners() {
        for listener in listeners {
            listener?.remove()
        }
        listeners.removeAll()
    }
}
