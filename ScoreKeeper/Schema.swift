import Foundation
import SQLiteData

@Table
struct Game: Identifiable {
    @Column(primaryKey: true)
    let id: UUID
    var title: String
}

@Table
struct Player: Identifiable {
    @Column(primaryKey: true)
    let id: UUID
    var gameID: Game.ID
    var name: String
    var score: Int
}

@Table
struct PlayerAsset: Identifiable {
    @Column("playerID", primaryKey: true)
    let id: Player.ID
    var imageData: Data
}

extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("Create initial tables") { db in
            try #sql(
                """
                CREATE TABLE "games" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "title" TEXT NOT NULL
                ) STRICT
                """
            )
            .execute(db)

            try #sql(
                """
                CREATE TABLE "players" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                  "gameID" TEXT NOT NULL REFERENCES "games"("id") ON DELETE CASCADE,
                  "name" TEXT NOT NULL,
                  "score" INTEGER NOT NULL
                ) STRICT
                """
            )
            .execute(db)

            try #sql(
                """
                CREATE INDEX IF NOT EXISTS "idx_players_gameID"
                ON "players"("gameID")
                """
            )
            .execute(db)

        }

        migrator.registerMigration("Create player assets table") { db in
            try #sql(
                """
                CREATE TABLE "playerAssets" (
                  "playerID" TEXT PRIMARY KEY NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
                  "imageData" BLOB NOT NULL
                ) STRICT
                """
            )
            .execute(db)
        }

        migrator.registerMigration("Seed initial data") { db in
            try #sql(
                """
                INSERT INTO "games" ("id", "title")
                VALUES
                  ('11111111-1111-1111-1111-111111111111', 'Practice Match'),
                  ('22222222-2222-2222-2222-222222222222', 'Championship')
                """
            )
            .execute(db)

            try #sql(
                """
                INSERT INTO "players" ("id", "gameID", "name", "score")
                VALUES
                  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1', '11111111-1111-1111-1111-111111111111', 'Alice', 12),
                  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2', '11111111-1111-1111-1111-111111111111', 'Bob', 9),
                  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3', '11111111-1111-1111-1111-111111111111', 'Eva', 15),
                  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4', '11111111-1111-1111-1111-111111111111', 'Frank', 11),
                  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', '22222222-2222-2222-2222-222222222222', 'Chris', 21),
                  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', '22222222-2222-2222-2222-222222222222', 'Diana', 18),
                  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3', '22222222-2222-2222-2222-222222222222', 'George', 16),
                  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb4', '22222222-2222-2222-2222-222222222222', 'Helen', 20)
                """
            )
            .execute(db)
        }

        try migrator.migrate(database)

        try database.write { db in
            try Player.createTemporaryTrigger(
                "players_prevent_negative_score_on_insert",
                before: .insert(
                    forEachRow: { _ in
                        Values(#sql("RAISE(FAIL, 'Player score cannot be negative')", as: Never.self))
                    },
                    when: { new in
                        new.score < 0
                    }
                )
            )
            .execute(db)

            try Player.createTemporaryTrigger(
                "players_prevent_negative_score_on_update",
                before: .update(
                    forEachRow: { _, _ in
                        Values(#sql("RAISE(FAIL, 'Player score cannot be negative')", as: Never.self))
                    },
                    when: { _, new in
                        new.score < 0
                    }
                )
            )
            .execute(db)
        }

        defaultDatabase = database
    }
}

