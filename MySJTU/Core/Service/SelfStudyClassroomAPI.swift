//
//  SelfStudyClassroomAPI.swift
//  MySJTU
//
//  Created by boar on 2026/03/24.
//

import Foundation
import Alamofire

struct SelfStudyClassroomAPI {
    private let baseURL = "https://ids.sjtu.edu.cn"

    struct Campus: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let indexNum: Int?
        let buildings: [Building]
    }

    struct Building: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let roomCode: String?
        let indexNum: Int?
    }

    struct SectionTime: Codable, Identifiable, Hashable, Sendable {
        let endTime: String
        let startTime: String
        let sectionIndex: Int

        var id: Int {
            sectionIndex
        }
    }

    struct ClosedRoom: Identifiable, Hashable, Sendable {
        let roomName: String
        let roomCode: String
        let date: String?
        let closedSections: Set<Int>

        var id: String {
            roomCode
        }
    }

    struct RoomCourse: Codable, Identifiable, Hashable, Sendable {
        let courseName: String
        let teacherName: String?
        let startSection: Int
        let endSection: Int

        var id: String {
            "\(courseName)-\(teacherName ?? "unknown")-\(startSection)-\(endSection)"
        }
    }

    struct Room: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let roomCode: String
        let indexNum: Int?
        /// `findBuildRoomType.freeRoom == "1"` 表示该教室是自习教室（不是“当前空闲”）
        let isSelfStudyRoom: Bool
        let courses: [RoomCourse]
        let actualStudentCount: Int?
    }

    struct Floor: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let indexNum: Int?
        let rooms: [Room]
    }

    struct BuildingSnapshot: Sendable {
        let floors: [Floor]
        let closedRooms: [ClosedRoom]
    }

    struct BuildingReference: Hashable, Sendable {
        let campusName: String
        let building: Building

        var displayName: String {
            "\(campusName)·\(building.name)"
        }
    }

    enum RoomStatusKind: String, Codable, Hashable, Sendable {
        case free = "空闲"
        case selfStudy = "自习教室"
        case occupied = "占用"
        case closed = "关闭"
    }

    struct RoomStatus: Hashable, Sendable {
        let kind: RoomStatusKind
        let currentCourse: RoomCourse?

        var statusText: String {
            kind.rawValue
        }

        var isAvailable: Bool {
            switch kind {
            case .free, .selfStudy:
                return true
            case .occupied, .closed:
                return false
            }
        }
    }

    struct BuildingRealtimeSnapshot: Sendable {
        let campusName: String
        let building: Building
        let floors: [Floor]
        let closedRooms: [ClosedRoom]
        let sections: [SectionTime]
        let currentSectionIndex: Int?

        var currentSection: SectionTime? {
            guard let currentSectionIndex else {
                return nil
            }
            return sections.first { $0.sectionIndex == currentSectionIndex }
        }
    }

    struct RoomRealtimeSnapshot: Sendable {
        let campusName: String
        let building: Building
        let floor: Floor
        let room: Room
        let closedSections: Set<Int>
        let sections: [SectionTime]
        let currentSectionIndex: Int?

        var currentSection: SectionTime? {
            guard let currentSectionIndex else {
                return nil
            }
            return sections.first { $0.sectionIndex == currentSectionIndex }
        }
    }

    struct RoomAttribute: Identifiable, Hashable, Sendable {
        let name: String
        let code: String
        let icon: String?
        let value: String
        let roomId: Int?

        var id: String {
            "\(code)-\(name)-\(value)"
        }
    }

    struct RoomEnvironmental: Hashable, Sendable {
        let sensorValues: [String: String]
        let sensorFlag: String?

        var hasSensor: Bool {
            sensorFlag?.uppercased() == "YES" || !sensorValues.isEmpty
        }
    }

    private struct IDSResponse<T: Decodable>: Decodable {
        let code: Int
        let msg: String
        let data: T?
    }

    private struct AreaBuildPayload: Decodable {
        let buildList: [BuildNode]
    }

    private struct BuildNode: Decodable {
        let id: Int
        let nodeId: Int?
        let name: String
        let roomCode: String?
        let indexNum: Int?
        let children: [BuildNode]?
    }

    private struct SectionPayload: Decodable {
        let section: [SectionTime]
        let curSection: Int?
    }

    private struct ClosedRoomPayload: Decodable {
        let closeSections: String?
        let date: String?
        let roomName: String
        let roomDm: String
        let sectionMap: [String: Int]?
    }

    private struct BuildRoomTypePayload: Decodable {
        let floorList: [FloorPayload]
    }

    private struct RoomAttributeListPayload: Decodable {
        let roomAttrList: [RoomAttributePayload]
    }

    private struct FloorPayload: Decodable {
        let id: Int
        let name: String
        let indexNum: Int?
        let roomStuNumbs: [RoomStudentPayload]?
        let children: [RoomPayload]?
    }

    private struct RoomStudentPayload: Decodable {
        let actualStuNum: Int?
        let roomId: Int?
    }

    private struct RoomPayload: Decodable {
        let id: Int
        let name: String
        let roomCode: String
        let indexNum: Int?
        let freeRoom: String?
        let roomCourseList: [RoomCourse]?
    }

    private struct RoomAttributePayload: Decodable {
        let name: String?
        let code: String?
        let icon: String?
        let value: String?
        let roomId: Int?
    }

    private struct RoomEnvironmentalPayload: Decodable {
        let sensor: LossyStringMap?
        let sensorFlag: String?
    }

    private struct RoomLookupPayload: Decodable {
        let teachBuilding: TeachBuildingPayload?
    }

    private struct TeachBuildingPayload: Decodable {
        let name: String?
    }

    private struct LossyStringMap: Decodable {
        let values: [String: String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var parsedValues: [String: String] = [:]

            for key in container.allKeys {
                if let value = try? container.decode(String.self, forKey: key) {
                    parsedValues[key.stringValue] = value
                    continue
                }

                if let value = try? container.decode(Int.self, forKey: key) {
                    parsedValues[key.stringValue] = String(value)
                    continue
                }

                if let value = try? container.decode(Double.self, forKey: key) {
                    parsedValues[key.stringValue] = String(value)
                    continue
                }

                if let value = try? container.decode(Bool.self, forKey: key) {
                    parsedValues[key.stringValue] = value ? "true" : "false"
                    continue
                }

                if (try? container.decodeNil(forKey: key)) == true {
                    continue
                }
            }

            self.values = parsedValues
        }
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    private func request<T: Decodable>(
        path: String,
        parameters: Parameters? = nil
    ) async throws -> IDSResponse<T> {
        let url = "\(baseURL)\(path)"
        let decoder = JSONDecoder()
        var hasBootstrappedSession = false

        while true {
            let data = try await AppAF.session.request(
                url,
                method: .post,
                parameters: parameters,
                encoding: URLEncoding.httpBody
            )
            .serializingData()
            .value

            do {
                return try decoder.decode(IDSResponse<T>.self, from: data)
            } catch {
                if isLikelySessionExpiredHTML(data), !hasBootstrappedSession {
                    hasBootstrappedSession = true
                    try await bootstrapSession()
                    continue
                }

                if isLikelySessionExpiredHTML(data) {
                    throw APIError.sessionExpired
                }
                throw error
            }
        }
    }

    private func isLikelySessionExpiredHTML(_ data: Data) -> Bool {
        guard let html = String(data: data, encoding: .utf8) else {
            return false
        }

        if html.contains("<html") || html.contains("<!DOCTYPE html") {
            return true
        }

        return html.localizedCaseInsensitiveContains("jaccount")
    }

    private func bootstrapSession() async throws {
        _ = try await AppAF.session.request("\(baseURL)/")
            .serializingData()
            .value
    }

    func fetchCampuses(schoolArea: Int = 0) async throws -> [Campus] {
        let response: IDSResponse<AreaBuildPayload> = try await request(
            path: "/build/findAreaBuild",
            parameters: [
                "schoolArea": schoolArea
            ]
        )

        guard response.code == 200 else {
            throw APIError.remoteError(response.msg)
        }

        guard let payload = response.data else {
            throw APIError.remoteError("服务器未返回校区和教学楼数据")
        }

        return payload.buildList
            .compactMap { campus in
                let buildings = (campus.children ?? [])
                    .map { building in
                        Building(
                            id: building.nodeId ?? building.id,
                            name: building.name,
                            roomCode: building.roomCode,
                            indexNum: building.indexNum
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.indexNum != rhs.indexNum {
                            return (lhs.indexNum ?? .max) < (rhs.indexNum ?? .max)
                        }
                        return lhs.name < rhs.name
                    }

                guard !buildings.isEmpty else {
                    return nil
                }

                return Campus(
                    id: campus.nodeId ?? campus.id,
                    name: campus.name,
                    indexNum: campus.indexNum,
                    buildings: buildings
                )
            }
            .sorted { lhs, rhs in
                if lhs.indexNum != rhs.indexNum {
                    return (lhs.indexNum ?? .max) < (rhs.indexNum ?? .max)
                }
                return lhs.name < rhs.name
            }
    }

    func fetchSections() async throws -> (sections: [SectionTime], currentSection: Int?) {
        let response: IDSResponse<SectionPayload> = try await request(
            path: "/course/findSection"
        )

        guard response.code == 200 else {
            throw APIError.remoteError(response.msg)
        }

        guard let payload = response.data else {
            throw APIError.remoteError("服务器未返回节次数据")
        }

        return (
            payload.section.sorted { $0.sectionIndex < $1.sectionIndex },
            payload.curSection
        )
    }

    func fetchClosedRooms(buildId: Int) async throws -> [ClosedRoom] {
        let response: IDSResponse<[ClosedRoomPayload]> = try await request(
            path: "/roomCloseState/findRoomAttrValueByCode",
            parameters: [
                "buildId": buildId
            ]
        )

        guard response.code == 200 else {
            throw APIError.remoteError(response.msg)
        }

        return (response.data ?? []).map { payload in
            var sections: Set<Int> = Set(
                (payload.closeSections ?? "")
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            )

            if let sectionMap = payload.sectionMap {
                for (key, value) in sectionMap where value == 0 {
                    if let section = Int(key) {
                        sections.insert(section)
                    }
                }
            }

            return ClosedRoom(
                roomName: payload.roomName,
                roomCode: payload.roomDm,
                date: payload.date,
                closedSections: sections
            )
        }
    }

    func fetchBuildingRoomUsage(buildId: Int) async throws -> [Floor] {
        let response: IDSResponse<BuildRoomTypePayload> = try await request(
            path: "/build/findBuildRoomType",
            parameters: [
                "buildId": buildId,
                "mobileType": "mobileFlag",
                "dayinweek": 3
            ]
        )

        guard response.code == 200 else {
            throw APIError.remoteError(response.msg)
        }

        guard let payload = response.data else {
            throw APIError.remoteError("服务器未返回教室占用数据")
        }

        let floors = payload.floorList
            .map { floor in
                let studentCountByRoomId: [Int: Int] = Dictionary(
                    uniqueKeysWithValues: (floor.roomStuNumbs ?? []).compactMap { item in
                        guard let roomId = item.roomId, let actualStuNum = item.actualStuNum else {
                            return nil
                        }
                        return (roomId, actualStuNum)
                    }
                )

                let rooms = (floor.children ?? [])
                    .map { room in
                        Room(
                            id: room.id,
                            name: room.name,
                            roomCode: room.roomCode,
                            indexNum: room.indexNum,
                            isSelfStudyRoom: room.freeRoom == "1",
                            courses: (room.roomCourseList ?? []).sorted {
                                if $0.startSection != $1.startSection {
                                    return $0.startSection < $1.startSection
                                }
                                return $0.endSection < $1.endSection
                            },
                            actualStudentCount: studentCountByRoomId[room.id]
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.indexNum != rhs.indexNum {
                            return (lhs.indexNum ?? .max) < (rhs.indexNum ?? .max)
                        }
                        return lhs.name < rhs.name
                    }

                return Floor(
                    id: floor.id,
                    name: floor.name,
                    indexNum: floor.indexNum,
                    rooms: rooms
                )
            }
            .sorted { lhs, rhs in
                if lhs.indexNum != rhs.indexNum {
                    return (lhs.indexNum ?? .max) < (rhs.indexNum ?? .max)
                }
                return lhs.name < rhs.name
            }

        await selfStudyRoomNameCache.store(floors: floors)
        return floors
    }

    func fetchBuildingSnapshot(buildId: Int) async throws -> BuildingSnapshot {
        async let floorsTask = fetchBuildingRoomUsage(buildId: buildId)
        async let closedTask = fetchClosedRooms(buildId: buildId)

        let floors = try await floorsTask
        let closedRooms = try await closedTask

        return BuildingSnapshot(
            floors: floors,
            closedRooms: closedRooms
        )
    }

    func fetchRoomPanoramaXMLURL(roomId: Int) async throws -> URL? {
        let response: IDSResponse<RoomAttributeListPayload> = try await request(
            path: "/roomAttr/findRoomAttrValueByCode",
            parameters: [
                "roomId": roomId,
                "code": "ROOM_ATTR_360"
            ]
        )

        guard response.code == 200 else {
            throw APIError.remoteError(response.msg)
        }

        let roomAttrList = response.data?.roomAttrList ?? []
        guard let panoramaItem = roomAttrList.first(where: { $0.code?.uppercased() == "ROOM_ATTR_360" }),
              let rawValue = panoramaItem.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        return panoramaXMLURL(from: rawValue)
    }

    func fetchRoomAttributes(roomId: Int) async throws -> [RoomAttribute] {
        let response: IDSResponse<RoomAttributeListPayload> = try await request(
            path: "/roomAttr/findRoomAttrValue",
            parameters: [
                "roomId": roomId
            ]
        )

        guard response.code == 200 else {
            throw APIError.remoteError(response.msg)
        }

        let roomAttrList = response.data?.roomAttrList ?? []
        return roomAttrList.compactMap { payload in
            guard let name = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let code = payload.code?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = payload.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  !code.isEmpty,
                  !value.isEmpty else {
                return nil
            }

            return RoomAttribute(
                name: name,
                code: code,
                icon: payload.icon,
                value: value,
                roomId: payload.roomId
            )
        }
    }

    func fetchRoomEnvironmental(roomId: Int) async throws -> RoomEnvironmental {
        let response: IDSResponse<RoomEnvironmentalPayload> = try await request(
            path: "/sensor/findRoomEnvironmental",
            parameters: [
                "roomId": roomId
            ]
        )

        guard response.code == 200 else {
            throw APIError.remoteError(response.msg)
        }

        let payload = response.data
        return RoomEnvironmental(
            sensorValues: payload?.sensor?.values ?? [:],
            sensorFlag: payload?.sensorFlag
        )
    }

    func fetchRoomDisplayName(roomId: Int) async throws -> String? {
        if let cachedName = await selfStudyRoomNameCache.name(for: roomId) {
            return cachedName
        }

        let response: IDSResponse<RoomLookupPayload> = try await request(
            path: "/build/findById",
            parameters: [
                "roomId": roomId
            ]
        )

        guard response.code == 200 else {
            throw APIError.remoteError(response.msg)
        }

        guard let name = response.data?.teachBuilding?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }

        await selfStudyRoomNameCache.store(name: name, for: roomId)
        return name
    }

    func fetchBuildingReferences(schoolArea: Int = 0) async throws -> [BuildingReference] {
        let campuses = try await fetchCampuses(schoolArea: schoolArea)
        return campuses.flatMap { campus in
            campus.buildings.map { building in
                BuildingReference(
                    campusName: campus.name,
                    building: building
                )
            }
        }
    }

    func fetchRealtimeBuildingSnapshot(
        named buildingName: String,
        schoolArea: Int = 0
    ) async throws -> BuildingRealtimeSnapshot {
        async let buildingReferencesTask = fetchBuildingReferences(schoolArea: schoolArea)
        async let sectionsTask = fetchSections()

        let buildingReferences = try await buildingReferencesTask
        let buildingReference = try resolveBuilding(named: buildingName, in: buildingReferences)
        async let snapshotTask = fetchBuildingSnapshot(buildId: buildingReference.building.id)

        let sectionPayload = try await sectionsTask
        let snapshot = try await snapshotTask
        let currentSectionIndex = effectiveCurrentSectionIndex(
            sections: sectionPayload.sections,
            serverCurrentSectionIndex: sectionPayload.currentSection
        )

        await selfStudyRoomLocationCache.store(
            campusName: buildingReference.campusName,
            building: buildingReference.building,
            floors: snapshot.floors
        )

        return BuildingRealtimeSnapshot(
            campusName: buildingReference.campusName,
            building: buildingReference.building,
            floors: snapshot.floors,
            closedRooms: snapshot.closedRooms,
            sections: sectionPayload.sections,
            currentSectionIndex: currentSectionIndex
        )
    }

    func fetchRealtimeRoomSnapshot(
        roomId: Int,
        schoolArea: Int = 0
    ) async throws -> RoomRealtimeSnapshot? {
        async let buildingReferencesTask = fetchBuildingReferences(schoolArea: schoolArea)
        async let sectionsTask = fetchSections()

        var firstLookupError: Error?
        let cachedEntry = await selfStudyRoomLocationCache.entry(for: roomId)
        let sectionPayload = try await sectionsTask
        let currentSectionIndex = effectiveCurrentSectionIndex(
            sections: sectionPayload.sections,
            serverCurrentSectionIndex: sectionPayload.currentSection
        )

        if let cachedEntry {
            do {
                let cachedSnapshot = try await fetchBuildingSnapshot(buildId: cachedEntry.buildingID)
                await selfStudyRoomLocationCache.store(
                    campusName: cachedEntry.campusName,
                    building: .init(
                        id: cachedEntry.buildingID,
                        name: cachedEntry.buildingName,
                        roomCode: nil,
                        indexNum: nil
                    ),
                    floors: cachedSnapshot.floors
                )

                if let matched = makeRoomRealtimeSnapshot(
                    roomId: roomId,
                    campusName: cachedEntry.campusName,
                    building: .init(
                        id: cachedEntry.buildingID,
                        name: cachedEntry.buildingName,
                        roomCode: nil,
                        indexNum: nil
                    ),
                    buildingSnapshot: cachedSnapshot,
                    sections: sectionPayload.sections,
                    currentSectionIndex: currentSectionIndex
                ) {
                    return matched
                }

                await selfStudyRoomLocationCache.remove(roomId: roomId)
            } catch {
                firstLookupError = error
            }
        }

        let buildingReferences = try await buildingReferencesTask

        for buildingReference in buildingReferences where buildingReference.building.id != cachedEntry?.buildingID {
            do {
                let snapshot = try await fetchBuildingSnapshot(buildId: buildingReference.building.id)
                await selfStudyRoomLocationCache.store(
                    campusName: buildingReference.campusName,
                    building: buildingReference.building,
                    floors: snapshot.floors
                )

                if let matched = makeRoomRealtimeSnapshot(
                    roomId: roomId,
                    campusName: buildingReference.campusName,
                    building: buildingReference.building,
                    buildingSnapshot: snapshot,
                    sections: sectionPayload.sections,
                    currentSectionIndex: currentSectionIndex
                ) {
                    return matched
                }
            } catch {
                if firstLookupError == nil {
                    firstLookupError = error
                }
            }
        }

        if let firstLookupError {
            throw firstLookupError
        }

        return nil
    }

    func closedSections(
        for room: Room,
        in closedRooms: [ClosedRoom]
    ) -> Set<Int> {
        let normalizedRoomCode = room.roomCode.uppercased()

        if let matchedByCode = closedRooms.first(where: { $0.roomCode.uppercased() == normalizedRoomCode }) {
            return matchedByCode.closedSections
        }

        if let matchedByName = closedRooms.first(where: { $0.roomName == room.name }) {
            return matchedByName.closedSections
        }

        return []
    }

    func roomStatus(
        for room: Room,
        in snapshot: BuildingRealtimeSnapshot
    ) -> RoomStatus {
        roomStatus(
            for: room,
            closedSections: closedSections(for: room, in: snapshot.closedRooms),
            totalSectionCount: snapshot.sections.count,
            currentSectionIndex: snapshot.currentSectionIndex
        )
    }

    func roomStatus(
        for room: Room,
        in snapshot: RoomRealtimeSnapshot
    ) -> RoomStatus {
        roomStatus(
            for: room,
            closedSections: snapshot.closedSections,
            totalSectionCount: snapshot.sections.count,
            currentSectionIndex: snapshot.currentSectionIndex
        )
    }

    func roomStatus(
        for room: Room,
        in snapshot: RoomRealtimeSnapshot,
        at sectionIndex: Int
    ) -> RoomStatus {
        roomStatus(
            for: room,
            closedSections: snapshot.closedSections,
            sectionIndex: sectionIndex
        )
    }

    func effectiveCurrentSectionIndex(
        sections: [SectionTime],
        serverCurrentSectionIndex: Int?
    ) -> Int? {
        if let localReferenceSectionIndex = sections.referenceSectionIndex() {
            return localReferenceSectionIndex
        }

        if sections.isEmpty,
           let serverCurrentSectionIndex {
            return serverCurrentSectionIndex
        }

        return nil
    }

    private func panoramaXMLURL(from rawURL: String) -> URL? {
        guard let sourceURL = URL(string: rawURL) else {
            return nil
        }

        let path = sourceURL.path
        let pathExtension = sourceURL.pathExtension.lowercased()

        if pathExtension == "xml" {
            return sourceURL
        }

        if path.hasSuffix("/") || pathExtension.isEmpty {
            return sourceURL.appendingPathComponent("pano.xml")
        }

        return sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("pano.xml")
    }

    private func makeRoomRealtimeSnapshot(
        roomId: Int,
        campusName: String,
        building: Building,
        buildingSnapshot: BuildingSnapshot,
        sections: [SectionTime],
        currentSectionIndex: Int?
    ) -> RoomRealtimeSnapshot? {
        guard let matchedFloorRoom = buildingSnapshot.floors.lazy.compactMap({ floor in
            floor.rooms.first(where: { $0.id == roomId }).map { (floor, $0) }
        }).first else {
            return nil
        }

        return RoomRealtimeSnapshot(
            campusName: campusName,
            building: building,
            floor: matchedFloorRoom.0,
            room: matchedFloorRoom.1,
            closedSections: closedSections(for: matchedFloorRoom.1, in: buildingSnapshot.closedRooms),
            sections: sections,
            currentSectionIndex: currentSectionIndex
        )
    }

    private func roomStatus(
        for room: Room,
        closedSections: Set<Int>,
        totalSectionCount: Int,
        currentSectionIndex: Int?
    ) -> RoomStatus {
        guard let currentSectionIndex else {
            if !closedSections.isEmpty && closedSections.count >= totalSectionCount {
                return .init(kind: .closed, currentCourse: nil)
            }

            return .init(
                kind: room.isSelfStudyRoom ? .selfStudy : .free,
                currentCourse: nil
            )
        }

        if closedSections.contains(currentSectionIndex) {
            return .init(kind: .closed, currentCourse: nil)
        }

        return roomStatus(
            for: room,
            closedSections: closedSections,
            sectionIndex: currentSectionIndex
        )
    }

    private func roomStatus(
        for room: Room,
        closedSections: Set<Int>,
        sectionIndex: Int
    ) -> RoomStatus {
        if closedSections.contains(sectionIndex) {
            return .init(kind: .closed, currentCourse: nil)
        }

        if let course = room.courses.first(where: {
            $0.startSection <= sectionIndex && $0.endSection >= sectionIndex
        }) {
            return .init(kind: .occupied, currentCourse: course)
        }

        return .init(
            kind: room.isSelfStudyRoom ? .selfStudy : .free,
            currentCourse: nil
        )
    }

    private func resolveBuilding(
        named rawBuildingName: String,
        in buildingReferences: [BuildingReference]
    ) throws -> BuildingReference {
        let normalizedQuery = Self.normalizedBuildingLookupKey(rawBuildingName)

        guard !normalizedQuery.isEmpty else {
            throw APIError.runtimeError(
                "教学楼名称不能为空。可用教学楼包括：\(Self.buildingReferenceListText(from: buildingReferences))"
            )
        }

        let exactMatches = buildingReferences.filter { reference in
            let normalizedName = Self.normalizedBuildingLookupKey(reference.building.name)
            let normalizedRoomCode = Self.normalizedBuildingLookupKey(reference.building.roomCode ?? "")
            return normalizedName == normalizedQuery || (!normalizedRoomCode.isEmpty && normalizedRoomCode == normalizedQuery)
        }

        if exactMatches.count == 1, let exactMatch = exactMatches.first {
            return exactMatch
        }

        if exactMatches.count > 1 {
            throw APIError.runtimeError(
                "找到了多个同名教学楼：\(Self.buildingReferenceListText(from: exactMatches, limit: 8))。请提供更精确的名称。"
            )
        }

        let partialMatches = buildingReferences.filter { reference in
            let normalizedName = Self.normalizedBuildingLookupKey(reference.building.name)
            let normalizedRoomCode = Self.normalizedBuildingLookupKey(reference.building.roomCode ?? "")

            return normalizedName.contains(normalizedQuery)
                || normalizedQuery.contains(normalizedName)
                || (!normalizedRoomCode.isEmpty && normalizedRoomCode.contains(normalizedQuery))
        }

        if partialMatches.count == 1, let partialMatch = partialMatches.first {
            return partialMatch
        }

        if partialMatches.count > 1 {
            throw APIError.runtimeError(
                "找到了多个匹配的教学楼：\(Self.buildingReferenceListText(from: partialMatches, limit: 8))。请提供更精确的名称。"
            )
        }

        throw APIError.runtimeError(
            "未找到名为“\(rawBuildingName)”的教学楼。可用教学楼包括：\(Self.buildingReferenceListText(from: buildingReferences))"
        )
    }

    private static func normalizedBuildingLookupKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "　", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
    }

    private static func buildingReferenceListText(
        from buildingReferences: [BuildingReference],
        limit: Int = 20
    ) -> String {
        let names = buildingReferences.map(\.displayName)
        guard names.count > limit else {
            return names.joined(separator: "、")
        }

        let prefix = names.prefix(limit).joined(separator: "、")
        return "\(prefix) 等 \(names.count) 个"
    }
}

private actor SelfStudyRoomLocationCache {
    struct Entry: Sendable {
        let campusName: String
        let buildingID: Int
        let buildingName: String
    }

    private var roomLocationByID: [Int: Entry] = [:]

    func entry(for roomId: Int) -> Entry? {
        roomLocationByID[roomId]
    }

    func store(
        campusName: String,
        building: SelfStudyClassroomAPI.Building,
        floors: [SelfStudyClassroomAPI.Floor]
    ) {
        for floor in floors {
            for room in floor.rooms {
                roomLocationByID[room.id] = Entry(
                    campusName: campusName,
                    buildingID: building.id,
                    buildingName: building.name
                )
            }
        }
    }

    func remove(roomId: Int) {
        roomLocationByID.removeValue(forKey: roomId)
    }
}

private let selfStudyRoomLocationCache = SelfStudyRoomLocationCache()

private actor SelfStudyRoomNameCache {
    private var roomNameByID: [Int: String] = [:]

    func name(for roomId: Int) -> String? {
        roomNameByID[roomId]
    }

    func store(name: String, for roomId: Int) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        roomNameByID[roomId] = trimmedName
    }

    func store(floors: [SelfStudyClassroomAPI.Floor]) {
        for floor in floors {
            for room in floor.rooms {
                let trimmedName = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else {
                    continue
                }

                roomNameByID[room.id] = trimmedName
            }
        }
    }
}

private let selfStudyRoomNameCache = SelfStudyRoomNameCache()

extension Array where Element == SelfStudyClassroomAPI.SectionTime {
    func referenceSection(for now: Date = .now) -> Element? {
        let resolvedSections = compactMap { section -> (section: Element, start: Date, end: Date)? in
            guard let start = now.timeOfDay("HH:mm", timeStr: section.startTime),
                  let end = now.timeOfDay("HH:mm", timeStr: section.endTime) else {
                return nil
            }
            return (section, start, end)
        }
        .sorted { lhs, rhs in
            if lhs.section.sectionIndex != rhs.section.sectionIndex {
                return lhs.section.sectionIndex < rhs.section.sectionIndex
            }
            return lhs.start < rhs.start
        }

        guard let firstSection = resolvedSections.first,
              let lastSection = resolvedSections.last,
              now >= firstSection.start,
              now <= lastSection.end else {
            return nil
        }

        if let currentSection = resolvedSections.first(where: { now >= $0.start && now <= $0.end }) {
            return currentSection.section
        }

        return resolvedSections.first(where: { now < $0.start })?.section
    }

    func referenceSectionIndex(for now: Date = .now) -> Int? {
        referenceSection(for: now)?.sectionIndex
    }
}
