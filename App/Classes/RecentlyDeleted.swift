import Engine
import Foundation

enum RecentlyDeleted {

    static func permanentlyDelete(picIDs: [String], in collectionID: String) async {
        let dataActor = DataActor.instance(for: collectionID)
        let ids = await dataActor.recentlyDeletedPicIDs(among: picIDs)
        guard !ids.isEmpty else { return }
        await dataActor.deletePics(withIDs: ids)
        await HashActor.instance(for: collectionID).deleteHashes(forPicIDs: ids)
        await PColorActor.instance(for: collectionID).deleteColors(forPicIDs: ids)
        Task.detached {
            await OriginalsManager.shared.deleteCloudOriginals(picIDs: ids, in: collectionID)
        }
    }

    static func purgeExpired(in collectionID: String) async {
        let ids = await DataActor.instance(for: collectionID)
            .recentlyDeletedPicIDs(deletedBefore: expiryCutoff())
        await permanentlyDelete(picIDs: ids, in: collectionID)
    }

    static func daysRemaining(for pic: Pic, now: Date = .now) -> Int {
        guard let dateDeleted = pic.dateDeleted,
              let expiry = Calendar.current.date(
                byAdding: .day, value: DataActor.recentlyDeletedRetentionDays, to: dateDeleted
              ) else { return DataActor.recentlyDeletedRetentionDays }
        let remaining = expiry.timeIntervalSince(now) / 86_400
        return max(Int(remaining.rounded(.up)), 0)
    }

    private static func expiryCutoff(now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: -DataActor.recentlyDeletedRetentionDays, to: now)
            ?? now
    }
}
