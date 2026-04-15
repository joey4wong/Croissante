import Foundation
import CryptoKit

@MainActor
class AudioCacheManager {
    static let shared = AudioCacheManager()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 5 * 1024 * 1024 * 1024
    private let cacheInfoFile: URL
    private var cacheInfo: [String: CacheInfo] = [:]
    
    private struct CacheInfo: Codable {
        let key: String
        let filePath: String
        let fileSize: Int64
        let creationDate: Date
        var lastAccessDate: Date
        var accessCount: Int
        
        init(key: String, filePath: String, fileSize: Int64) {
            self.key = key
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
    }
    
    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("TTSAudio", isDirectory: true)
        cacheInfoFile = cacheDirectory.appendingPathComponent("cacheInfo.json")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadCacheInfo()
    }
    
    func cacheAudioData(_ data: Data, forText text: String) -> URL? {
        let cacheKey = generateCacheKey(for: text)
        
        do {
            let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).mp3")
            try data.write(to: fileURL)
            
            let info = CacheInfo(key: cacheKey, filePath: fileURL.lastPathComponent, fileSize: Int64(data.count))
            cacheInfo[cacheKey] = info
            
            saveCacheInfo()
            enforceCacheSizeLimit()
            
            return fileURL
        } catch {
            return nil
        }
    }
    
    func getCachedAudioURL(forText text: String) -> URL? {
        let cacheKey = generateCacheKey(for: text)
        
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
    
    func hasCachedAudio(forText text: String) -> Bool {
        let cacheKey = generateCacheKey(for: text)
        guard let info = cacheInfo[cacheKey] else { return false }
        let fileURL = cacheDirectory.appendingPathComponent(info.filePath)
        return fileManager.fileExists(atPath: fileURL.path)
    }
    
    func clearCache() {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try fileManager.removeItem(at: fileURL)
            }
            cacheInfo.removeAll()
            saveCacheInfo()
        } catch {}
    }
    
    func getCacheSize() -> Int64 {
        cacheInfo.values.reduce(0) { $0 + $1.fileSize }
    }
    
    func getCacheFileCount() -> Int {
        cacheInfo.count
    }
    
    private func generateCacheKey(for text: String) -> String {
        let data = Data(text.utf8)
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
