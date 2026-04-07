// 会话持久化：每个会话存为 Documents/sessions/{id}.json
import Foundation

final class SessionStore {
    static let shared = SessionStore()
    private(set) var sessions: [ChatSession] = []
    private let fm = FileManager.default

    private var sessionsDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("sessions", isDirectory: true)
    }

    private init() {
        try? fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true, attributes: nil)
        reload()
    }

    private func fileURL(for id: String) -> URL {
        sessionsDir.appendingPathComponent("\(id).json")
    }

    private func reload() {
        sessions = []
        guard let files = try? fm.contentsOfDirectory(at: sessionsDir,
                                                       includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let s = try? decoder.decode(ChatSession.self, from: data) {
                sessions.append(s)
            }
        }
        sort()
    }

    private func sort() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    func save(_ session: ChatSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(session) {
            try? data.write(to: fileURL(for: session.id), options: .atomic)
        }
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        sort()
    }

    func delete(id: String) {
        try? fm.removeItem(at: fileURL(for: id))
        sessions.removeAll { $0.id == id }
    }

    func clearAll() {
        try? fm.removeItem(at: sessionsDir)
        try? fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true, attributes: nil)
        sessions = []
    }

    func get(id: String) -> ChatSession? {
        sessions.first { $0.id == id }
    }
}
