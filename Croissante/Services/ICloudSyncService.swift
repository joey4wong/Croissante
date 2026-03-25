import Foundation

@MainActor
final class ICloudSyncService {
    static let shared = ICloudSyncService()

    private enum Keys {
        static let learningPayload = "icloud_learning_sync_payload_v1"
    }

    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let maxPayloadBytes = 900_000
    private let pushDebounceNanoseconds: UInt64 = 900_000_000
    private var externalChangeObserver: NSObjectProtocol?
    private var remotePayloadHandler: ((Data) -> Void)?
    private var pendingPushTask: Task<Void, Never>?
    private var lastQueuedPayloadFingerprint: Int?
    private var lastPushedPayloadFingerprint: Int?
    private(set) var isEnabled = false

    private init() {}

    func configure(isEnabled: Bool, onRemotePayload: @escaping (Data) -> Void) {
        remotePayloadHandler = onRemotePayload
        setEnabled(isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled

        if enabled {
            startObserving()
            ubiquitousStore.synchronize()
            if let payload = payloadData() {
                remotePayloadHandler?(payload)
            }
        } else {
            stopObserving()
            pendingPushTask?.cancel()
            pendingPushTask = nil
            lastQueuedPayloadFingerprint = nil
        }
    }

    func payloadData() -> Data? {
        if let data = ubiquitousStore.data(forKey: Keys.learningPayload) {
            return data
        }
        if let payloadString = ubiquitousStore.string(forKey: Keys.learningPayload) {
            return payloadString.data(using: .utf8)
        }
        return nil
    }

    func push(payload: Data) {
        guard isEnabled else { return }
        guard payload.count <= maxPayloadBytes else { return }

        let fingerprint = payload.hashValue
        if lastQueuedPayloadFingerprint == fingerprint || lastPushedPayloadFingerprint == fingerprint {
            return
        }

        lastQueuedPayloadFingerprint = fingerprint
        pendingPushTask?.cancel()

        let delay = pushDebounceNanoseconds
        pendingPushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.commitPush(payload: payload, fingerprint: fingerprint)
        }
    }

    private func startObserving() {
        guard externalChangeObserver == nil else { return }
        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] notification in
            guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
                return
            }
            guard changedKeys.contains(Keys.learningPayload) else { return }
            Task { @MainActor [weak self] in
                self?.handleExternalChange()
            }
        }
    }

    private func stopObserving() {
        guard let observer = externalChangeObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        externalChangeObserver = nil
    }

    private func handleExternalChange() {
        guard isEnabled else { return }
        guard let payload = payloadData() else { return }
        if payload.hashValue == lastPushedPayloadFingerprint {
            return
        }
        remotePayloadHandler?(payload)
    }

    private func commitPush(payload: Data, fingerprint: Int) {
        pendingPushTask = nil
        guard isEnabled else { return }
        guard payload.count <= maxPayloadBytes else { return }
        ubiquitousStore.set(payload, forKey: Keys.learningPayload)
        ubiquitousStore.synchronize()
        lastQueuedPayloadFingerprint = nil
        lastPushedPayloadFingerprint = fingerprint
    }
}
