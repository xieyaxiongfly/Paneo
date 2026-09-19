import Foundation

struct SavedWorkspace: Codable {
    var id: UUID
    var name: String
    var layout: SavedNode
}

struct WorkspaceArchive: Codable {
    var selectedID: UUID
    var workspaces: [SavedWorkspace]
}
