import Foundation
import CryptoKit

enum AudioCacheNamespace: String, Codable {
    case official
    case userOverride
}

@MainActor
class AudioCacheManager {
    static let shared = AudioCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 3 * 1024 * 1024 * 1024
    private let cacheInfoFile: URL
    private var cacheInfo: [String: CacheInfo] = [:]
    
    private struct CacheInfo: Codable {
        let key: String
        let namespace: AudioCacheNamespace
        let filePath: String
        let fileSize: Int64
        let creationDate: Date
        var lastAccessDate: Date
        var accessCount: Int
        
        init(key: String, namespace: AudioCacheNamespace, filePath: String, fileSize: Int64) {
            self.key = key
            self.namespace = namespace
            self.filePath = filePath
            self.fileSize = fileSize
            self.creationDate = Date()
            self.lastAccessDate = Date()
            self.accessCount = 1
        }
        
        mutating func updateAccess() {
            self.lastAccessDate = Date()
            self.accessCount += 1
        }

        private enum CodingKeys: String, CodingKey {
            case key
            case namespace
            case filePath
            case fileSize
            case creationDate
            case lastAccessDate
            case accessCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            namespace = try container.decodeIfPresent(AudioCacheNamespace.self, forKey: .namespace) ?? .official
            filePath = try container.decode(String.self, forKey: .filePath)
            fileSize = try container.decode(Int64.self, forKey: .fileSize)
            creationDate = try container.decode(Date.self, forKey: .creationDate)
            lastAccessDate = try container.decode(Date.self, forKey: .lastAccessDate)
            accessCount = try container.decode(Int.self, forKey: .accessCount)
        }
    }
    
    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("TTSAudio", isDirectory: true)
        cacheInfoFile = cacheDirectory.appendingPathComponent("cacheInfo.json")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadCacheInfo()
    }
    
    func cacheAudioData(_ data: Data, forText text: String, namespace: AudioCacheNamespace = .official) -> URL? {
        let cacheKey = generateCacheKey(for: text, namespace: namespace)
        
        do {
            let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).mp3")
            try data.write(to: fileURL)
            
            let info = CacheInfo(
                key: cacheKey,
                namespace: namespace,
                filePath: fileURL.lastPathComponent,
                fileSize: Int64(data.count)
            )
            cacheInfo[cacheKey] = info
            
            saveCacheInfo()
            enforceCacheSizeLimit()
            
            return fileURL
        } catch {
            return nil
        }
    }
    
    func getCachedAudioURL(forText text: String, namespace: AudioCacheNamespace = .official) -> URL? {
        let cacheKey = generateCacheKey(for: text, namespace: namespace)
        
        guard var info = cacheInfo[cacheKey] else { return nil }
        
        let fileURL = cacheDirectory.appendingPathComponent(info.filePath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cacheInfo.removeValue(forKey: cacheKey)
            saveCacheInfo()
            return nil
        }
        
        info.updateAccess()
        cacheInfo[cacheKey] = info
        saveCacheInfo()
        
        return fileURL
    }
    
    func hasCachedAudio(forText text: String, namespace: AudioCacheNamespace = .official) -> Bool {
        let cacheKey = generateCacheKey(for: text, namespace: namespace)
        guard let info = cacheInfo[cacheKey] else { return false }
        let fileURL = cacheDirectory.appendingPathComponent(info.filePath)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    func clearCache(namespace: AudioCacheNamespace? = nil) {
        do {
            if let namespace {
                let entries = cacheInfo.filter { $0.value.namespace == namespace }
                for (key, info) in entries {
                    let fileURL = cacheDirectory.appendingPathComponent(info.filePath)
                    try? fileManager.removeItem(at: fileURL)
                    cacheInfo.removeValue(forKey: key)
                }
            } else {
                let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    try fileManager.removeItem(at: fileURL)
                }
                cacheInfo.removeAll()
            }
            saveCacheInfo()
        } catch {}
    }
    
    func getCacheSize() -> Int64 {
        cacheInfo.values.reduce(0) { $0 + $1.fileSize }
    }
    
    func getCacheFileCount() -> Int {
        cacheInfo.count
    }
    
    private func generateCacheKey(for text: String, namespace: AudioCacheNamespace) -> String {
        let data = Data("\(namespace.rawValue)|\(text)".utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func loadCacheInfo() {
        guard fileManager.fileExists(atPath: cacheInfoFile.path) else {
            cacheInfo = [:]
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheInfoFile)
            cacheInfo = try JSONDecoder().decode([String: CacheInfo].self, from: data)
            
            cacheInfo = cacheInfo.filter { _, info in
                let fileURL = cacheDirectory.appendingPathComponent(info.filePath)
                return fileManager.fileExists(atPath: fileURL.path)
            }
        } catch {
            cacheInfo = [:]
        }
    }
    
    private func saveCacheInfo() {
        do {
            let data = try JSONEncoder().encode(cacheInfo)
            try data.write(to: cacheInfoFile)
        } catch {}
    }
    
    private func enforceCacheSizeLimit() {
        var currentSize = getCacheSize()
        guard currentSize > maxCacheSize else { return }
        
        let sortedEntries = cacheInfo.sorted { $0.value.lastAccessDate < $1.value.lastAccessDate }
        
        for (key, info) in sortedEntries {
            guard currentSize > maxCacheSize else { break }
            
            let fileURL = cacheDirectory.appendingPathComponent(info.filePath)
            do {
                try fileManager.removeItem(at: fileURL)
                cacheInfo.removeValue(forKey: key)
                currentSize -= info.fileSize
            } catch {}
        }
        
        saveCacheInfo()
    }
    
    func performMaintenance() {
        enforceCacheSizeLimit()
    }
}
