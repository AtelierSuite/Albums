@preconcurrency import CloudKit
import Engine
import Foundation

extension SyncMate: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)
        case .fetchedRecordZoneChanges(let changes):
            await debugLog("↓ \(changes.modifications.count) mod \(changes.deletions.count) del")
            await applyFetchedRecordZoneChanges(changes)
        case .sentRecordZoneChanges(let changes):
            await debugLog("↑ \(changes.savedRecords.count) sent \(changes.failedRecordSaves.count) fail")
            await handleSentRecordZoneChanges(changes, syncEngine: syncEngine)
        case .accountChange(let change):
            await debugLog("account change")
            handleAccountChange(change)
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        var records: [CKRecord.ID: CKRecord] = [:]
        for change in pending {
            if case .saveRecord(let recordID) = change {
                if let record = await buildRecord(for: recordID) {
                    records[recordID] = record
                } else {
                    syncEngine.state.remove(pendingRecordZoneChanges: [change])
                }
            }
        }
        let builtRecords = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            builtRecords[recordID]
        }
    }

    // MARK: - Build records (upload)

    private func buildRecord(for recordID: CKRecord.ID) async -> CKRecord? {
        if recordID.zoneID.zoneName == Self.librariesZoneName {
            guard let library = await LibrariesActor.shared.librarySyncSnapshot(forID: recordID.recordName) else {
                return nil
            }
            return libraryRecord(from: library, recordID: recordID)
        }
        let collectionID = Self.collectionID(forZone: recordID.zoneID)
        let dataActor = DataActor.instance(for: collectionID)
        let name = recordID.recordName
        if let albumID = AlbumPreferences.albumID(fromRecordName: name) {
            guard let preferences = await dataActor.preferencesSyncSnapshot(forAlbumID: albumID) else { return nil }
            return preferencesRecord(from: preferences, recordID: recordID)
        }
        if let album = await dataActor.albumSyncSnapshot(forID: name) {
            return albumRecord(from: album, recordID: recordID)
        }
        if let pic = await dataActor.picSyncSnapshot(forID: name) {
            return picRecord(from: pic, recordID: recordID)
        }
        return nil
    }

    private func libraryRecord(from snapshot: LibrarySyncSnapshot, recordID: CKRecord.ID) -> CKRecord {
        let record = baseRecord(snapshot.systemFields, recordID: recordID, type: SyncRecordType.library)
        record["name"] = snapshot.name
        record["coverPicIDs"] = snapshot.coverPicIDs.isEmpty ? nil : snapshot.coverPicIDs
        record["coverPicIDsTracked"] = 1
        return record
    }

    private func albumRecord(from snapshot: AlbumSyncSnapshot, recordID: CKRecord.ID) -> CKRecord {
        let record = baseRecord(snapshot.systemFields, recordID: recordID, type: SyncRecordType.album)
        record["name"] = snapshot.name
        record["parentAlbumID"] = snapshot.parentAlbumID
        record["dateCreated"] = Date(timeIntervalSince1970: snapshot.dateCreated)
        record["coverPhoto"] = snapshot.coverPhoto
        record["coverPhotoTracked"] = 1
        return record
    }

    private func picRecord(from snapshot: PicSyncSnapshot, recordID: CKRecord.ID) -> CKRecord {
        let record = baseRecord(snapshot.systemFields, recordID: recordID, type: SyncRecordType.pic)
        record["name"] = snapshot.name
        record["containingAlbumID"] = snapshot.albumID
        record["dateAdded"] = Date(timeIntervalSince1970: snapshot.dateAdded)
        record["mediaType"] = snapshot.mediaType
        record["duration"] = snapshot.duration
        record["thumbnail"] = snapshot.thumbnail
        record["pinnedDate"] = snapshot.pinnedAt.map { Date(timeIntervalSince1970: $0) }
        record["dateDeleted"] = snapshot.dateDeleted.map { Date(timeIntervalSince1970: $0) }
        return record
    }

    private func preferencesRecord(from snapshot: AlbumPreferencesSyncSnapshot, recordID: CKRecord.ID) -> CKRecord {
        let record = baseRecord(snapshot.systemFields, recordID: recordID, type: SyncRecordType.albumPreferences)
        let preferences = snapshot.preferences
        record["albumID"] = preferences.albumID
        record["albumSort"] = preferences.albumSort
        record["albumViewStyle"] = preferences.albumViewStyle
        record["albumColumnCount"] = preferences.albumColumnCount
        record["picSort"] = preferences.picSort
        record["picColumnCount"] = preferences.picColumnCount
        record["hideSectionHeaders"] = preferences.hideSectionHeaders
        return record
    }

    private func baseRecord(_ systemFields: Data?, recordID: CKRecord.ID, type: String) -> CKRecord {
        if let systemFields, let record = Self.decodeSystemFields(systemFields) {
            return record
        }
        return CKRecord(recordType: type, recordID: recordID)
    }

    // MARK: - Apply fetched changes (download)

    private func applyFetchedRecordZoneChanges(
        _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) async {
        var libraryChanged = false
        var removedLibraryIDs: [String] = []
        var changedCoverAlbumIDs: [String] = []
        for modification in changes.modifications {
            if modification.record.recordID.zoneID.zoneName == Self.librariesZoneName {
                libraryChanged = true
            }
            if await applyRecord(modification.record) {
                let recordID = modification.record.recordID
                await CoverCacheActor.instance(for: Self.collectionID(forZone: recordID.zoneID))
                    .deleteCover(forAlbumWithID: recordID.recordName)
                changedCoverAlbumIDs.append(recordID.recordName)
            }
        }
        var deletedPicIDsByCollection: [String: [String]] = [:]
        for deletion in changes.deletions {
            if deletion.recordID.zoneID.zoneName == Self.librariesZoneName {
                libraryChanged = true
                removedLibraryIDs.append(deletion.recordID.recordName)
                await LibrariesActor.shared.removeLibraryForRemoteDelete(id: deletion.recordID.recordName)
                continue
            }
            let dataActor = DataActor.instance(for: Self.collectionID(forZone: deletion.recordID.zoneID))
            if deletion.recordType == SyncRecordType.album {
                await dataActor.removeAlbumForRemoteDelete(id: deletion.recordID.recordName)
            } else if deletion.recordType == SyncRecordType.albumPreferences {
                if let albumID = AlbumPreferences.albumID(fromRecordName: deletion.recordID.recordName) {
                    await dataActor.removePreferencesForRemoteDelete(albumID: albumID)
                }
            } else {
                await dataActor.removePicForRemoteDelete(id: deletion.recordID.recordName)
                await OriginalsManager.shared.deleteCloudOriginal(
                    picID: deletion.recordID.recordName, in: dataActor.collectionID
                )
                deletedPicIDsByCollection[dataActor.collectionID, default: []]
                    .append(deletion.recordID.recordName)
            }
        }
        // Purge local-only derived caches (hashes, colors) for remotely-deleted pics.
        for (collectionID, picIDs) in deletedPicIDsByCollection {
            await HashActor.instance(for: collectionID).deleteHashes(forPicIDs: picIDs)
            await PColorActor.instance(for: collectionID).deleteColors(forPicIDs: picIDs)
        }
        if !changes.modifications.isEmpty || !changes.deletions.isEmpty {
            let removedLibraryIDs = removedLibraryIDs
            let changedCoverAlbumIDs = changedCoverAlbumIDs
            await MainActor.run {
                NotificationCenter.default.post(name: .syncDidApplyRemoteChanges, object: changedCoverAlbumIDs)
                if libraryChanged {
                    NotificationCenter.default.post(name: .syncDidApplyLibraryChanges,
                                                    object: removedLibraryIDs)
                }
            }
        }
    }

    @discardableResult
    private func applyRecord(_ record: CKRecord) async -> Bool {
        let systemFields = Self.encodeSystemFields(record)
        let modified = (record.modificationDate ?? Date.now).timeIntervalSince1970
        if record.recordID.zoneID.zoneName == Self.librariesZoneName {
            await LibrariesActor.shared.applyRemoteLibrary(Self.librarySnapshot(
                from: record, systemFields: systemFields, lastModified: modified
            ))
            return false
        }
        let dataActor = DataActor.instance(for: Self.collectionID(forZone: record.recordID.zoneID))
        if record.recordType == SyncRecordType.album {
            return await dataActor.applyRemoteAlbum(AlbumSyncSnapshot(
                id: record.recordID.recordName,
                name: record["name"] as? String ?? "",
                parentAlbumID: record["parentAlbumID"] as? String,
                dateCreated: (record["dateCreated"] as? Date)?.timeIntervalSince1970 ?? 0,
                coverPhoto: record["coverPhoto"] as? Data,
                includesCoverPhoto: record["coverPhotoTracked"] != nil,
                systemFields: systemFields,
                lastModified: modified
            ))
        } else if record.recordType == SyncRecordType.albumPreferences {
            if let preferences = Self.albumPreferences(from: record) {
                await dataActor.applyRemotePreferences(AlbumPreferencesSyncSnapshot(
                    preferences: preferences, systemFields: systemFields
                ))
            }
        } else if record.recordType == SyncRecordType.pic {
            await dataActor.applyRemotePic(PicSyncSnapshot(
                id: record.recordID.recordName,
                name: record["name"] as? String ?? "",
                albumID: record["containingAlbumID"] as? String,
                dateAdded: (record["dateAdded"] as? Date)?.timeIntervalSince1970 ?? 0,
                mediaType: record["mediaType"] as? Int ?? 0,
                duration: record["duration"] as? Double,
                thumbnail: record["thumbnail"] as? Data,
                pinnedAt: (record["pinnedDate"] as? Date)?.timeIntervalSince1970,
                dateDeleted: (record["dateDeleted"] as? Date)?.timeIntervalSince1970,
                systemFields: systemFields,
                lastModified: modified
            ))
        }
        return false
    }

    // MARK: - Handle sent changes

    private func handleSentRecordZoneChanges(
        _ changes: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        for record in changes.savedRecords {
            let systemFields = Self.encodeSystemFields(record)
            if record.recordType == SyncRecordType.library {
                await LibrariesActor.shared.markLibrarySynced(id: record.recordID.recordName,
                                                              systemFields: systemFields)
                continue
            }
            let collectionID = Self.collectionID(forZone: record.recordID.zoneID)
            let dataActor = DataActor.instance(for: collectionID)
            if record.recordType == SyncRecordType.album {
                await dataActor.markAlbumSynced(id: record.recordID.recordName, systemFields: systemFields)
            } else if record.recordType == SyncRecordType.albumPreferences {
                if let albumID = AlbumPreferences.albumID(fromRecordName: record.recordID.recordName) {
                    await dataActor.markPreferencesSynced(albumID: albumID, systemFields: systemFields)
                }
            } else {
                await dataActor.markPicSynced(id: record.recordID.recordName, systemFields: systemFields)
                await OriginalsManager.shared.uploadOriginal(picID: record.recordID.recordName,
                                                             in: collectionID)
            }
        }
        for recordID in changes.deletedRecordIDs {
            if recordID.zoneID.zoneName == Self.librariesZoneName {
                await LibrariesActor.shared.removeLibraryTombstone(id: recordID.recordName)
            } else {
                await DataActor.instance(for: Self.collectionID(forZone: recordID.zoneID))
                    .removeTombstone(id: recordID.recordName)
            }
        }
        for failure in changes.failedRecordSaves {
            await handleFailedSave(failure, syncEngine: syncEngine)
        }
    }

    private func handleFailedSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine
    ) async {
        let recordID = failure.record.recordID
        let error = failure.error
        if error.code == .serverRecordChanged,
           let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
            let collectionID = Self.collectionID(forZone: recordID.zoneID)
            if recordID.zoneID.zoneName != Self.librariesZoneName,
               isForcePushing(collectionID) {
                let serverFields = Self.encodeSystemFields(serverRecord)
                let dataActor = DataActor.instance(for: collectionID)
                if failure.record.recordType == SyncRecordType.album {
                    await dataActor.markAlbumSynced(id: recordID.recordName, systemFields: serverFields)
                } else if let albumID = AlbumPreferences.albumID(fromRecordName: recordID.recordName) {
                    await dataActor.markPreferencesSynced(albumID: albumID, systemFields: serverFields)
                } else {
                    await dataActor.markPicSynced(id: recordID.recordName, systemFields: serverFields)
                }
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            } else {
                await applyRecord(serverRecord)
            }
        } else if error.code == .zoneNotFound {
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: recordID.zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signOut, .switchAccounts:
            clearState()
        default:
            break
        }
    }

    static func albumPreferences(from record: CKRecord) -> AlbumPreferences? {
        guard let albumID = AlbumPreferences.albumID(fromRecordName: record.recordID.recordName) else { return nil }
        let defaults = AlbumPreferences.defaults
        return AlbumPreferences(
            albumID: albumID,
            albumSort: record["albumSort"] as? String ?? defaults.albumSort,
            albumViewStyle: record["albumViewStyle"] as? String ?? defaults.albumViewStyle,
            albumColumnCount: record["albumColumnCount"] as? Int ?? defaults.albumColumnCount,
            picSort: record["picSort"] as? String ?? defaults.picSort,
            picColumnCount: record["picColumnCount"] as? Int ?? defaults.picColumnCount,
            hideSectionHeaders: record["hideSectionHeaders"] as? Bool ?? defaults.hideSectionHeaders
        )
    }

    static func librarySnapshot(from record: CKRecord, systemFields: Data,
                                lastModified: Double) -> LibrarySyncSnapshot {
        LibrarySyncSnapshot(
            id: record.recordID.recordName,
            name: record["name"] as? String ?? "",
            coverPicIDs: record["coverPicIDs"] as? [String] ?? [],
            includesCoverPicIDs: record["coverPicIDsTracked"] != nil,
            systemFields: systemFields,
            lastModified: lastModified
        )
    }

    // MARK: - System fields (de)serialization

    static func encodeSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        return archiver.encodedData
    }

    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        let record = CKRecord(coder: unarchiver)
        unarchiver.finishDecoding()
        return record
    }
}
