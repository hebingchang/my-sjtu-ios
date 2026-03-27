//
//  BusModels.swift
//  MySJTU
//
//  Created by boar on 2026/03/25.
//

import Foundation
import CoreLocation
import Alamofire

enum BusAPI {
    private static let baseURL = "https://sjtu-bus.dyweb.sjtu.cn/api/v1/shuttle"

    private struct Envelope<Payload: Decodable>: Decodable {
        let success: Bool
        let message: String
        let data: Payload?
        let code: Int
    }

    struct Station: Decodable, Identifiable, Equatable, Sendable {
        let id: Int
        let name: String
        let latitude: CLLocationDegrees
        let longitude: CLLocationDegrees
        let lines: [Line]
        let routeBadges: [BusRouteBadge]

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case latitude
            case longitude
            case lines
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
            longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
            lines = try container.decode([Line].self, forKey: .lines)
            routeBadges = uniqueLines(lines).map { line in
                BusRouteBadge(
                    lineCode: line.lineCode,
                    title: line.abbreviation.isEmpty ? line.name : line.abbreviation
                )
            }
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    struct Line: Decodable, Identifiable, Equatable, Sendable {
        let id: Int
        let lineCode: String
        let name: String
        let direction: Int
        let startStation: String
        let endStation: String
        let abbreviation: String

        enum CodingKeys: String, CodingKey {
            case id
            case lineCode = "line_code"
            case name
            case direction
            case startStation = "start_station"
            case endStation = "end_station"
            case abbreviation
        }
    }

    struct Destination: Decodable, Equatable, Sendable {
        let code: String
        let name: String
    }

    struct NextDeparture: Decodable, Equatable, Sendable {
        let time: String
        let timeInt: Int
        let executionDate: String
        let type: String

        enum CodingKeys: String, CodingKey {
            case time
            case timeInt = "time_int"
            case executionDate = "execution_date"
            case type
        }
    }

    struct Departure: Decodable, Identifiable, Equatable, Sendable {
        struct StationReference: Decodable, Equatable, Sendable {
            let id: Int
        }

        let line: Line
        let destination: Destination
        let station: StationReference?
        let next: NextDeparture?

        var id: String {
            "\(line.lineCode)-\(line.direction)-\(destination.code)-\(next?.executionDate ?? "none")-\(next?.timeInt ?? -1)"
        }
    }

    struct StationNext: Decodable, Equatable, Sendable {
        let station: Station
        let departures: [Departure]
    }

    struct Route: Decodable, Equatable, Sendable {
        private let id: Int
        private let lineID: Int
        let coordinates: [CLLocationCoordinate2D]

        enum CodingKeys: String, CodingKey {
            case id
            case lineID = "line_id"
            case route
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            lineID = try container.decode(Int.self, forKey: .lineID)
            coordinates = Self.parseCoordinates(
                try container.decode(String.self, forKey: .route)
            )
        }

        private static func parseCoordinates(
            _ route: String
        ) -> [CLLocationCoordinate2D] {
            route.split(separator: ",").compactMap { segment in
                let points = segment
                    .split(separator: " ")
                    .compactMap { Double(String($0)) }

                guard points.count == 2 else {
                    return nil
                }

                return CLLocationCoordinate2D(
                    latitude: points[1],
                    longitude: points[0]
                )
            }
        }

        static func == (
            lhs: Self,
            rhs: Self
        ) -> Bool {
            guard lhs.id == rhs.id,
                  lhs.lineID == rhs.lineID,
                  lhs.coordinates.count == rhs.coordinates.count else {
                return false
            }

            return zip(lhs.coordinates, rhs.coordinates).allSatisfy { lhsCoordinate, rhsCoordinate in
                lhsCoordinate.latitude == rhsCoordinate.latitude
                    && lhsCoordinate.longitude == rhsCoordinate.longitude
            }
        }
    }

    struct LineStation: Decodable, Identifiable, Equatable, Sendable {
        struct Detail: Decodable, Equatable, Sendable {
            struct Location: Decodable, Equatable, Sendable {
                let latitude: CLLocationDegrees
                let longitude: CLLocationDegrees

                var coordinate: CLLocationCoordinate2D {
                    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                }
            }

            let id: Int
            let stationCode: String
            let name: String
            let location: Location
            let time: Int

            enum CodingKeys: String, CodingKey {
                case id
                case stationCode = "station_code"
                case name
                case location
                case time
            }
        }

        let id: Int
        let lineID: Int
        let stationCode: String
        let station: Detail
        let index: Int
        let time: Int

        enum CodingKeys: String, CodingKey {
            case id
            case lineID = "line_id"
            case stationCode = "station_code"
            case station
            case index
            case time
        }
    }

    struct TimetableEntry: Decodable, Identifiable, Equatable, Sendable {
        let time: String
        let timeInt: Int
        let executionDate: String
        let type: String
        let scheduledDate: Date?

        enum CodingKeys: String, CodingKey {
            case time
            case timeInt = "time_int"
            case executionDate = "execution_date"
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decode(String.self, forKey: .time)
            timeInt = try container.decode(Int.self, forKey: .timeInt)
            executionDate = try container.decode(String.self, forKey: .executionDate)
            type = try container.decode(String.self, forKey: .type)
            scheduledDate = BusScheduleClock.scheduledDate(
                executionDate: executionDate,
                timeText: time
            )
        }

        var id: String {
            "\(executionDate)-\(timeInt)-\(type)"
        }
    }

    struct RealtimeVehicle: Decodable, Identifiable, Equatable, Sendable {
        struct Location: Decodable, Equatable, Sendable {
            let latitude: CLLocationDegrees
            let longitude: CLLocationDegrees

            var coordinate: CLLocationCoordinate2D {
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }

        let location: Location
        let angle: CLLocationDirection
        let vehicleCode: String
        let remark: String
        let speed: Double
        let station: String
        let direction: Int
        let updatedAt: Date
        let inStation: Bool

        enum CodingKeys: String, CodingKey {
            case location
            case angle
            case vehicleCode = "vehicle_code"
            case remark
            case speed
            case station
            case direction
            case updatedAt = "updated_at"
            case inStation = "in_station"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            location = try container.decode(Location.self, forKey: .location)
            angle = try container.decodeIfPresent(CLLocationDirection.self, forKey: .angle) ?? 0
            vehicleCode = try container.decode(String.self, forKey: .vehicleCode)
            remark = try container.decodeIfPresent(String.self, forKey: .remark) ?? ""
            speed = try container.decodeIfPresent(Double.self, forKey: .speed)
                ?? Double(try container.decodeIfPresent(Int.self, forKey: .speed) ?? 0)
            station = try container.decodeIfPresent(String.self, forKey: .station) ?? ""
            direction = try container.decodeIfPresent(Int.self, forKey: .direction) ?? 0

            let timestamp = try container.decodeIfPresent(Double.self, forKey: .updatedAt)
                ?? Double(try container.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0)
            updatedAt = Date(timeIntervalSince1970: timestamp / 1000)

            let inStationValue = try container.decodeIfPresent(Int.self, forKey: .inStation) ?? 0
            inStation = inStationValue != 0
        }

        var id: String {
            vehicleCode
        }

        var coordinate: CLLocationCoordinate2D {
            location.coordinate
        }
    }

    static func fetchStations() async throws -> [Station] {
        let response = try await request("\(baseURL)/stations", payloadType: [Station].self)
        return response
    }

    static func fetchNextDepartures(stationID: Int) async throws -> StationNext {
        try await request("\(baseURL)/stations/\(stationID)/next", payloadType: StationNext.self)
    }

    static func fetchRoute(
        lineCode: String,
        direction: Int
    ) async throws -> Route? {
        let response = try await request(
            "\(baseURL)/\(lineCode)/\(direction)/route",
            payloadType: [Route].self
        )
        return response.first
    }

    static func fetchLineStations(
        lineCode: String,
        direction: Int
    ) async throws -> [LineStation] {
        try await request(
            "\(baseURL)/\(lineCode)/\(direction)/stations",
            payloadType: [LineStation].self
        )
    }

    static func fetchTimetable(
        lineCode: String,
        direction: Int,
        stationID: Int
    ) async throws -> [TimetableEntry] {
        try await request(
            "\(baseURL)/\(lineCode)/\(direction)/timetable/\(stationID)",
            payloadType: [TimetableEntry].self
        )
    }

    static func realtimeMonitorURL(
        lineCode: String,
        direction: Int
    ) -> URL? {
        URL(
            string: "wss://sjtu-bus.dyweb.sjtu.cn/ws/v1/shuttle/\(lineCode)/\(direction)/monitor/ws"
        )
    }

    static func decodeRealtimeVehicles(
        from data: Data
    ) throws -> [RealtimeVehicle] {
        try JSONDecoder().decode([RealtimeVehicle].self, from: data)
    }

    private static func request<Payload: Decodable>(
        _ url: String,
        payloadType: Payload.Type
    ) async throws -> Payload {
        let envelope = try await AF.request(
            url,
            parameters: ["r": Date.now.timeIntervalSince1970],
            encoding: URLEncoding(destination: .queryString)
        )
        .validate()
        .serializingDecodable(Envelope<Payload>.self)
        .value

        guard envelope.success else {
            throw APIError.remoteError(envelope.message)
        }

        guard envelope.code == 0 else {
            throw APIError.runtimeError(envelope.message)
        }

        guard let data = envelope.data else {
            throw APIError.runtimeError(envelope.message)
        }

        return data
    }
}

struct BusRouteBadge: Identifiable, Hashable, Sendable {
    let lineCode: String
    let title: String

    var id: String {
        lineCode
    }
}

struct BusDepartureCard: Identifiable, Equatable, Sendable {
    struct Direction: Identifiable, Equatable, Sendable {
        struct DestinationGroup: Identifiable, Equatable, Sendable {
            let destinationCode: String
            let destinationName: String
            let departures: [Departure]

            var id: String {
                destinationCode
            }
        }

        let lineCode: String
        let direction: Int
        let title: String
        let endStation: String
        let departures: [Departure]
        let destinationGroups: [DestinationGroup]

        var id: String {
            "\(lineCode)-\(direction)"
        }

        init(
            lineCode: String,
            direction: Int,
            title: String,
            endStation: String,
            departures: [Departure]
        ) {
            self.lineCode = lineCode
            self.direction = direction
            self.title = title
            self.endStation = endStation
            self.departures = departures
            destinationGroups = Self.makeDestinationGroups(from: departures)
        }

        private static func makeDestinationGroups(
            from departures: [Departure]
        ) -> [DestinationGroup] {
            var departuresByDestination: [String: [Departure]] = [:]
            var destinationOrder: [String] = []

            for departure in departures {
                if departuresByDestination[departure.destinationCode] == nil {
                    destinationOrder.append(departure.destinationCode)
                }

                departuresByDestination[departure.destinationCode, default: []].append(departure)
            }

            return destinationOrder.compactMap { destinationCode in
                guard
                    let groupedDepartures = departuresByDestination[destinationCode],
                    let firstDeparture = groupedDepartures.first
                else {
                    return nil
                }

                return DestinationGroup(
                    destinationCode: destinationCode,
                    destinationName: firstDeparture.destinationName,
                    departures: groupedDepartures
                )
            }
        }
    }

    struct Departure: Identifiable, Equatable, Sendable {
        let stationID: Int?
        let destinationCode: String
        let destinationName: String
        let timeText: String?
        let timeInt: Int?
        let executionDate: String?
        let type: String?
        let scheduledDate: Date?

        init(
            stationID: Int?,
            destinationCode: String,
            destinationName: String,
            timeText: String?,
            timeInt: Int?,
            executionDate: String?,
            type: String?
        ) {
            self.stationID = stationID
            self.destinationCode = destinationCode
            self.destinationName = destinationName
            self.timeText = timeText
            self.timeInt = timeInt
            self.executionDate = executionDate
            self.type = type
            if let executionDate, let timeText {
                scheduledDate = BusScheduleClock.scheduledDate(
                    executionDate: executionDate,
                    timeText: timeText
                )
            } else {
                scheduledDate = nil
            }
        }

        var id: String {
            "\(destinationCode)-\(executionDate ?? "none")-\(timeInt ?? -1)-\(type ?? "none")"
        }

        var hasUpcomingDeparture: Bool {
            timeText != nil && timeInt != nil && executionDate != nil
        }

        var displayTimeText: String {
            timeText ?? "暂无"
        }
    }

    let lineCode: String
    let name: String
    let badgeTitle: String
    let directions: [Direction]

    var id: String {
        lineCode
    }

    static func makeCards(
        for station: BusAPI.Station,
        departures: [BusAPI.Departure]
    ) -> [BusDepartureCard] {
        let uniqueStationLines = uniqueLines(station.lines)

        return uniqueStationLines.compactMap { primaryLine in
            let allLinesForRoute = uniqueDirections(
                station.lines
                    .filter { $0.lineCode == primaryLine.lineCode }
                    .sorted { lhs, rhs in
                        if lhs.direction != rhs.direction {
                            return lhs.direction < rhs.direction
                        }
                        return lhs.id < rhs.id
                    }
            )

            let routeDepartures = departures.filter { $0.line.lineCode == primaryLine.lineCode }
            guard !routeDepartures.isEmpty else {
                return nil
            }

            let availableDirections = uniqueDirections(
                routeDepartures
                    .map(\.line)
                    .sorted { lhs, rhs in
                        if lhs.direction != rhs.direction {
                            return lhs.direction < rhs.direction
                        }

                        return lhs.id < rhs.id
                    }
            )

            let directions = availableDirections.enumerated()
                .map { availableIndex, departureLine in
                    let line = allLinesForRoute.first(where: { $0.direction == departureLine.direction })
                        ?? departureLine
                    let groupedDepartures = routeDepartures
                        .filter { $0.line.direction == line.direction }
                        .sorted(by: departureSort)
                        .map {
                            Departure(
                                stationID: $0.station?.id,
                                destinationCode: $0.destination.code,
                                destinationName: $0.destination.name,
                                timeText: $0.next?.time,
                                timeInt: $0.next?.timeInt,
                                executionDate: $0.next?.executionDate,
                                type: $0.next?.type
                            )
                        }

                    let fallbackIndex = allLinesForRoute.firstIndex(where: { $0.direction == line.direction })
                        ?? (allLinesForRoute.count + availableIndex)

                    return (
                        index: fallbackIndex,
                        direction: Direction(
                            lineCode: line.lineCode,
                            direction: line.direction,
                            title: directionTitle(for: line, in: allLinesForRoute),
                            endStation: line.endStation,
                            departures: groupedDepartures
                        )
                    )
                }
                .sorted { lhs, rhs in
                    directionSort(
                        lhs: lhs.direction,
                        rhs: rhs.direction,
                        lhsFallbackIndex: lhs.index,
                        rhsFallbackIndex: rhs.index
                    )
                }
                .map(\.direction)

            return BusDepartureCard(
                lineCode: primaryLine.lineCode,
                name: primaryLine.name,
                badgeTitle: primaryLine.abbreviation.isEmpty ? primaryLine.name : primaryLine.abbreviation,
                directions: directions
            )
        }
    }
}

enum BusScheduleClock {
    static let shuttleTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func scheduledDate(
        executionDate: String,
        timeText: String
    ) -> Date? {
        let dateParts = executionDate.split(separator: "-").compactMap { Int($0) }
        let timeParts = timeText.split(separator: ":").compactMap { Int($0) }

        guard dateParts.count == 3, timeParts.count == 2 else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = shuttleTimeZone
        components.year = dateParts[0]
        components.month = dateParts[1]
        components.day = dateParts[2]
        components.hour = timeParts[0]
        components.minute = timeParts[1]
        components.second = 0

        return calendar.date(from: components)
    }

    static func relativeDescription(
        for departure: BusDepartureCard.Departure,
        now: Date = .now
    ) -> String? {
        guard let scheduledDate = departure.scheduledDate else {
            return nil
        }

        return relativeDescription(for: scheduledDate, now: now)
    }

    static func relativeDescription(
        for entry: BusAPI.TimetableEntry,
        now: Date = .now
    ) -> String? {
        guard let scheduledDate = entry.scheduledDate else {
            return nil
        }

        return relativeDescription(for: scheduledDate, now: now)
    }

    static func dayDescription(
        for executionDate: String,
        now: Date = .now
    ) -> String {
        guard let scheduledDate = scheduledDate(
            executionDate: executionDate,
            timeText: "00:00"
        ) else {
            return executionDate
        }

        let dayOffset = calendar.dateComponents(
            [.day],
            from: startOfDay(for: now),
            to: startOfDay(for: scheduledDate)
        ).day ?? 0

        switch dayOffset {
        case 0:
            return "今天"
        case 1:
            return "明天"
        case 2:
            return "后天"
        default:
            return executionDate
        }
    }

    private static func relativeDescription(
        for scheduledDate: Date,
        now: Date
    ) -> String? {
        let minutes = Int(scheduledDate.timeIntervalSince(now) / 60)
        if minutes < 0 {
            return nil
        }

        if minutes == 0 {
            return "即将发车"
        }

        if minutes < 60 {
            return "\(minutes) 分钟后"
        }

        let dayOffset = calendar.dateComponents([.day], from: startOfDay(for: now), to: startOfDay(for: scheduledDate)).day ?? 0
        if dayOffset == 0 {
            return "今天"
        }

        if dayOffset == 1 {
            return "明天"
        }

        if dayOffset == 2 {
            return "后天"
        }

        return nil
    }

    static func formatTime(
        _ date: Date
    ) -> String {
        timeFormatter.string(from: date)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shuttleTimeZone
        return calendar
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = shuttleTimeZone
        return formatter
    }()

    private static func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}

private func uniqueLines(_ lines: [BusAPI.Line]) -> [BusAPI.Line] {
    var seenLineCodes = Set<String>()
    return lines.filter { line in
        seenLineCodes.insert(line.lineCode).inserted
    }
}

private func uniqueDirections(_ lines: [BusAPI.Line]) -> [BusAPI.Line] {
    var seenDirections = Set<Int>()
    return lines.filter { line in
        seenDirections.insert(line.direction).inserted
    }
}

private func departureSort(
    lhs: BusAPI.Departure,
    rhs: BusAPI.Departure
) -> Bool {
    switch (lhs.next, rhs.next) {
    case let (lhsNext?, rhsNext?):
        if lhsNext.executionDate != rhsNext.executionDate {
            return lhsNext.executionDate < rhsNext.executionDate
        }

        if lhsNext.timeInt != rhsNext.timeInt {
            return lhsNext.timeInt < rhsNext.timeInt
        }

    case (.some, nil):
        return true

    case (nil, .some):
        return false

    case (nil, nil):
        break
    }

    if lhs.destination.name != rhs.destination.name {
        return lhs.destination.name < rhs.destination.name
    }

    return lhs.destination.code < rhs.destination.code
}

private func directionSort(
    lhs: BusDepartureCard.Direction,
    rhs: BusDepartureCard.Direction,
    lhsFallbackIndex: Int,
    rhsFallbackIndex: Int
) -> Bool {
    switch (
        lhs.departures.first(where: { $0.hasUpcomingDeparture }),
        rhs.departures.first(where: { $0.hasUpcomingDeparture })
    ) {
    case let (lhsDeparture?, rhsDeparture?):
        guard
            let lhsExecutionDate = lhsDeparture.executionDate,
            let rhsExecutionDate = rhsDeparture.executionDate,
            let lhsTimeInt = lhsDeparture.timeInt,
            let rhsTimeInt = rhsDeparture.timeInt
        else {
            return lhsFallbackIndex < rhsFallbackIndex
        }

        if lhsExecutionDate != rhsExecutionDate {
            return lhsExecutionDate < rhsExecutionDate
        }

        if lhsTimeInt != rhsTimeInt {
            return lhsTimeInt < rhsTimeInt
        }

    case (.some, nil):
        return true

    case (nil, .some):
        return false

    case (nil, nil):
        break
    }

    return lhsFallbackIndex < rhsFallbackIndex
}

private func directionTitle(
    for line: BusAPI.Line,
    in lines: [BusAPI.Line]
) -> String {
    let hasBothDirections = Set(lines.map(\.direction)).count > 1
    let isLoopRoute = line.startStation == line.endStation
        || (hasBothDirections && Set(lines.map(\.endStation)).count == 1)
    if isLoopRoute {
        return line.direction == 0 ? "顺时针" : "逆时针"
    }

    return line.endStation
}
