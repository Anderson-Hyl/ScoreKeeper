import Dependencies
import SQLiteData
import SwiftUI

struct GamesView: View {
    @FetchAll(
        Game
            .group(by: \.id)
            .leftJoin(Player.all) { $0.id.eq($1.gameID) }
            .select { Row.Columns(game: $0, playerCount: $1.count()) },
        animation: .default
    )
    private var rows
    @Dependency(\.defaultDatabase) private var database

    @State private var isPresentingAddGameAlert = false
    @State private var newGameTitle = ""

    var body: some View {
        List {
            ForEach(rows) { row in
                NavigationLink {
                    GameView(game: row.game)
                } label: {
                    HStack {
                        Text(row.game.title)
                            .font(.headline)
                        Spacer()
                        Text("\(row.playerCount)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteGames)
        }
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Game") {
                    isPresentingAddGameAlert = true
                }
            }
        }
        .alert("Add Game", isPresented: $isPresentingAddGameAlert) {
            TextField("Title", text: $newGameTitle)
            Button("Cancel", role: .cancel) {
                newGameTitle = ""
            }
            Button("Save") {
                saveGame()
            }
            .disabled(newGameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a game title")
        }
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView("No Games", systemImage: "list.bullet.rectangle")
            }
        }
    }

    @Selection
    struct Row: Identifiable {
        let game: Game
        let playerCount: Int

        var id: Game.ID { game.id }
    }

    private func saveGame() {
        let title = newGameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        do {
            try database.write { db in
                try Game.insert {
                    Game.Draft(title: title)
                }
                .execute(db)
            }
            newGameTitle = ""
        } catch {
            print("Failed to save game: \(error)")
        }
    }

    private func deleteGames(at offsets: IndexSet) {
        let ids = offsets.map { rows[$0].game.id }

        do {
            try database.write { db in
                for id in ids {
                    try Game.find(id).delete().execute(db)
                }
            }
        } catch {
            print("Failed to delete games: \(error)")
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }

    NavigationStack {
        GamesView()
    }
}
