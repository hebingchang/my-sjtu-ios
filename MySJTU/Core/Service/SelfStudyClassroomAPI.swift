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

    struct Campus: Identifiable, Hashable {
        let id: Int
        let name: String
        let indexNum: Int?
        let buildings: [Building]
    }

    struct Building: Identifiable, Hashable {
        let id: Int
        let name: String
        let roomCode: String?
        let indexNum: Int?
    }

    struct SectionTime: Codable, Identifiable, Hashable {
        let endTime: String
        let startTime: String
        let sectionIndex: Int

        var id: Int {
            sectionIndex
        }
    }

    struct ClosedRoom: Identifiable, Hashable {
        let roomName: String
        let roomCode: String
        let date: String?
        let closedSections: Set<Int>

        var id: String {
            roomCode
        }
    }

    struct RoomCourse: Codable, Identifiable, Hashable {
        let courseName: String
        let teacherName: String?
        let startSection: Int
        let endSection: Int

        var id: String {
            "\(courseName)-\(teacherName ?? "unknown")-\(startSection)-\(endSection)"
        }
    }

    struct Room: Identifiable, Hashable {
        let id: Int
        let name: String
        let roomCode: String
        let indexNum: Int?
        /// `findBuildRoomType.freeRoom == "1"` 表示该教室是自习教室（不是“当前空闲”）
        let isSelfStudyRoom: Bool
        let courses: [RoomCourse]
        let actualStudentCount: Int?
    }

    struct Floor: Identifiable, Hashable {
        let id: Int
        let name: String
        let indexNum: Int?
        let rooms: [Room]
    }

    struct BuildingSnapshot {
        let floors: [Floor]
        let closedRooms: [ClosedRoom]
    }

    struct RoomAttribute: Identifiable, Hashable {
        let name: String
        let code: String
        let icon: String?
        let value: String
        let roomId: Int?

        var id: String {
            "\(code)-\(name)-\(value)"
        }
    }

    struct RoomEnvironmental: Hashable {
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
            let data = try await AF.request(
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
        _ = try await AF.request("\(baseURL)/")
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

        return payload.floorList
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
}

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
