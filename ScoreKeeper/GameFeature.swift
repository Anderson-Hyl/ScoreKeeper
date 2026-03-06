import Dependencies
import IssueReporting
import PhotosUI
import SQLiteData
import SwiftUI
import UIKit

@MainActor
@Observable
final class GameViewModel {
    let game: Game
    var isScoreAscending = true
    var errorMessage: String?

    var isPresentingAddPlayerAlert = false
    var newPlayerName = ""

    var isPresentingPhotoPicker = false
    var selectedPhotoItem: PhotosPickerItem?
    var photoTargetPlayer: Player?
    var photoActionPlayer: Player?

    @ObservationIgnored @Dependency(\.defaultDatabase) var database
    @ObservationIgnored @FetchAll(Row.none, animation: .default) var rows

    init(game: Game) {
        self.game = game
    }

    func toggleScoreSortButtonTapped() {
        isScoreAscending.toggle()
    }

    func addPlayerToolbarButtonTapped() {
        isPresentingAddPlayerAlert = true
    }

    func addPlayerSaveButtonTapped() {
        let name = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isPresentingAddPlayerAlert = false
        newPlayerName = ""

        withErrorReporting {
            try database.write { db in
                try Player.insert {
                    Player.Draft(gameID: game.id, name: name, score: 0)
                }
                .execute(db)
            }
        }
    }

    func avatarButtonTapped(row: Row) {
        if row.imageData == nil {
            photoTargetPlayer = row.player
            isPresentingPhotoPicker = true
        } else {
            photoActionPlayer = row.player
        }
    }

    func selectNewPhotoButtonTapped() {
        guard let player = photoActionPlayer else { return }
        photoActionPlayer = nil
        photoTargetPlayer = player
        isPresentingPhotoPicker = true
    }

    func removePhotoFromDialogButtonTapped() {
        guard let player = photoActionPlayer else { return }
        photoActionPlayer = nil
        removePhotoButtonTapped(playerID: player.id)
    }

    func photoPickerSelectionChanged() async {
        guard
            let item = selectedPhotoItem,
            let player = photoTargetPlayer
        else { return }

        defer {
            selectedPhotoItem = nil
            photoTargetPlayer = nil
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                addOrReplacePhotoButtonTapped(playerID: player.id, imageData: data)
            }
        } catch {
            reportIssue(error)
            errorMessage = "Failed to load selected photo."
        }
    }

    func reloadPlayers() async {
        let query = Player
            .where { $0.gameID.eq(game.id) }
            .leftJoin(PlayerAsset.all) { $0.id.eq($1.id) }
            .order { player, _ in
                if isScoreAscending {
                    player.score.asc()
                } else {
                    player.score.desc()
                }
            }
            .select { Row.Columns(player: $0, imageData: $1.imageData) }

        _ = await withErrorReporting {
            try await $rows.load(query)
        }
    }

    func incrementScoreButtonTapped(player: Player) {
        adjustScore(for: player, delta: 1)
    }

    func decrementScoreButtonTapped(player: Player) {
        adjustScore(for: player, delta: -1)
    }

    func addOrReplacePhotoButtonTapped(playerID: Player.ID, imageData: Data) {
        let draft = PlayerAsset.Draft(id: playerID, imageData: imageData)

        let didSucceed = withErrorReporting {
            try database.write { db in
                try PlayerAsset.upsert {
                    draft
                }
                .execute(db)
            }
            return true
        } ?? false

        if !didSucceed {
            errorMessage = "Failed to save player photo."
        }
    }

    func removePhotoButtonTapped(playerID: Player.ID) {
        let didSucceed = withErrorReporting {
            try database.write { db in
                try PlayerAsset.find(playerID).delete().execute(db)
            }
            return true
        } ?? false

        if !didSucceed {
            errorMessage = "Failed to remove player photo."
        }
    }

    private func adjustScore(for player: Player, delta: Int) {
        let updatedPlayer: Player = {
            var player = player
            player.score += delta
            return player
        }()

        let didSucceed = withErrorReporting {
            try database.write { db in
                try Player.update(updatedPlayer).execute(db)
            }
            return true
        } ?? false

        if !didSucceed {
            errorMessage = "Player score cannot be negative."
        }
    }

    @Selection
    struct Row: Identifiable {
        let player: Player
        let imageData: Data?

        var id: Player.ID { player.id }
    }
}

struct GameView: View {
    @State private var model: GameViewModel

    init(game: Game) {
        _model = State(initialValue: GameViewModel(game: game))
    }

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                if model.rows.isEmpty {
                    if model.$rows.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        ContentUnavailableView("No Players", systemImage: "person.2.slash")
                    }
                } else {
                    ForEach(model.rows) { row in
                        HStack(spacing: 12) {
                            Button {
                                model.avatarButtonTapped(row: row)
                            } label: {
                                avatarView(imageData: row.imageData)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)

                            Text(row.player.name)

                            Spacer()

                            HStack(spacing: 8) {
                                Button {
                                    model.decrementScoreButtonTapped(player: row.player)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)

                                Text("\(row.player.score)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()

                                Button {
                                    model.incrementScoreButtonTapped(player: row.player)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Players (\(model.rows.count))")
                    Spacer()
                    Button(model.isScoreAscending ? "Score ↑" : "Score ↓") {
                        model.toggleScoreSortButtonTapped()
                    }
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle(model.game.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Player") {
                    model.addPlayerToolbarButtonTapped()
                }
            }
        }
        .alert("Add Player", isPresented: $model.isPresentingAddPlayerAlert) {
            TextField("Name", text: $model.newPlayerName)
            Button("Cancel", role: .cancel) {
                model.newPlayerName = ""
            }
            Button("Save") {
                model.addPlayerSaveButtonTapped()
            }
            .disabled(model.newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a player name")
        }
        .confirmationDialog(
            "Player Photo",
            isPresented: Binding(
                get: { model.photoActionPlayer != nil },
                set: { isPresented in
                    if !isPresented {
                        model.photoActionPlayer = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Select New Photo") {
                model.selectNewPhotoButtonTapped()
            }

            Button("Remove Photo", role: .destructive) {
                model.removePhotoFromDialogButtonTapped()
            }

            Button("Cancel", role: .cancel) {
                model.photoActionPlayer = nil
            }
        }
        .photosPicker(
            isPresented: $model.isPresentingPhotoPicker,
            selection: $model.selectedPhotoItem,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .alert(
            "Error",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task(id: model.selectedPhotoItem) {
            await withErrorReporting {
                await model.photoPickerSelectionChanged()
            }
        }
        .task(id: model.isScoreAscending) {
            await withErrorReporting {
                await model.reloadPlayers()
            }
        }
    }

    @ViewBuilder
    private func avatarView(imageData: Data?) -> some View {
        if
            let imageData,
            let image = UIImage(data: imageData)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFill()
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        try $0.bootstrapDatabase()
    }

    NavigationStack {
        GameView(game: Game(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, title: "Practice Match"))
    }
}
