from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='angrove-rc-audit-') as temp:
    temp = Path(temp)
    models = (root/'Angrove-iOS/Models/InquiryModels.swift').read_text().split('/// Decides whether an otherwise new conversation')[0].replace('import SwiftUI', '')
    cipher = (root/'WidgetShared/LocalDataEncryption.swift').read_text().split('nonisolated enum LocalDataKeychain')[0]
    (temp/'Models.swift').write_text(models)
    (temp/'Cipher.swift').write_text(cipher)
    (temp/'Fixtures.swift').write_text('''import Foundation
import CryptoKit
import Security
nonisolated struct ConceptDefinition: Codable, Hashable { let word: String }
nonisolated struct UploadedFile: Codable, Hashable { let name: String }
nonisolated struct GroundingSourceSummary: Codable, Equatable {}
nonisolated enum ResponseEvidenceBasis: String, Codable { case fixture }
nonisolated enum ChatBlock: Codable, Hashable { case text(String); case user(String, ConceptDefinition?, [UploadedFile]) }
nonisolated enum DailyQuestionWidgetStore { static func migrate() throws {}; static func discard() {} }
// In-memory key provider: never touches the owner's Keychain.
nonisolated enum LocalDataKeychain {
 static let fixtureKey = SymmetricKey(size: .bits256)
 static func key(service: String, accessGroup: String? = nil, accessible: CFString = kSecAttrAccessibleWhenUnlocked, create: Bool) throws -> SymmetricKey { fixtureKey }
 static func remove(service: String) throws {}
}
''')
    (temp/'Main.swift').write_text('''import Foundation
@main struct RCAudit {
 static func main() throws {
  let base = FileManager.default.temporaryDirectory.appending(path: "rc-fixtures-" + UUID().uuidString)
  let suite = "rc-fixtures." + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { try? FileManager.default.removeItem(at: base); defaults.removePersistentDomain(forName: suite) }
  func snapshot(_ title: String) -> InquiryPersistenceSnapshot { .init(conversations: [.init(title: title)], activeConversationID: nil) }
  let fixed = Date.now
  let store = InquirySnapshotFileStore(rootDirectory: base.appending(path: "import"), defaults: defaults, now: { fixed })
  try store.save(snapshot("A"))
  try store.save(snapshot("B-latest-user-work"))
  try store.importData(JSONEncoder().encode(snapshot("C-imported")))
  let backups = try FileManager.default.contentsOfDirectory(at: base.appending(path: "import/Backups"), includingPropertiesForKeys: nil)
  let backupTitles = try backups.map { try JSONDecoder().decode(InquiryPersistenceSnapshot.self, from: EncryptedPersonalFile.read($0)).conversations.first!.title }
  print("IMPORT: live=\\(store.load()!.conversations.first!.title), backup titles=\\(backupTitles)")
  precondition(!backupTitles.contains("B-latest-user-work"))
  let collision = InquirySnapshotFileStore(rootDirectory: base.appending(path: "collision"), defaults: defaults, now: { fixed })
  try collision.save(snapshot("old"))
  let live = base.appending(path: "collision/conversations-v1.json")
  try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: live.path)
  try collision.save(snapshot("first-edit-after-idle"))
  var rejected = false
  do { try collision.save(snapshot("second-edit-same-second")) } catch { rejected = true; print("BACKUP COLLISION: \\(error)") }
  precondition(rejected)
  print("BACKUP COLLISION: retained=\\(collision.load()!.conversations.first!.title)")
  var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot("legacy"))) as! [String: Any]
  var conversations = json["conversations"] as! [[String: Any]]
  conversations[0].removeValue(forKey: "createdAt")
  json["conversations"] = conversations
  let legacy = try JSONSerialization.data(withJSONObject: json)
  var legacyRejected = false
  do { _ = try JSONDecoder().decode(InquiryPersistenceSnapshot.self, from: legacy) } catch { legacyRejected = true; print("LEGACY: \\(error)") }
  precondition(legacyRejected)
  let legacyRoot = base.appending(path: "legacy")
  try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
  try legacy.write(to: legacyRoot.appending(path: "conversations-v1.json"))
  let legacyStore = InquirySnapshotFileStore(rootDirectory: legacyRoot, defaults: defaults)
  print("LEGACY STORE: load returned nil=\\(legacyStore.load() == nil)")
  precondition(legacyStore.load() == nil)
  print("All three defect reproductions confirmed.")
 }
}
''')
    sources = [temp/'Fixtures.swift', temp/'Models.swift', temp/'Cipher.swift', root/'Angrove-iOS/Persistence/PrivatePreferences.swift', root/'Angrove-iOS/Persistence/InquiryPersistence.swift', temp/'Main.swift']
    subprocess.run(['xcrun', 'swiftc', *map(str, sources), '-o', str(temp/'audit')], check=True)
    subprocess.run([str(temp/'audit')], check=True)
