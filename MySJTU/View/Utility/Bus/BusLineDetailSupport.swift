//
//  BusLineDetailSupport.swift
//  MySJTU
//

import CoreLocation
import Foundation

// MARK: - Line Detail Selection

struct BusLineDestinationOption: Identifiable, Equatable {
    let code: String
    let name: String
    let timetableTypes: [String]

    var id: String {
        code
    }
}

enum BusLineDirectionFilterMode: String, Identifiable {
    case all
    case special

    var id: String {
        rawValue
    }
}

struct BusLineDirectionFilterOption: Identifiable, Equatable {
    let mode: BusLineDirectionFilterMode
    let title: String

    var id: String {
        mode.rawValue
    }
}

enum BusShuttleScheduleType: String {
    case outboundNormal = "out/normal"
    case normal = "normal"
    case normalInbound = "normal/in"
}

struct BusLineDetailSelection: Identifiable, Equatable {
    let station: BusAPI.Station
    let currentStopID: Int?
    let lineCode: String
    let lineName: String
    let badgeTitle: String
    let direction: Int
    let directionTitle: String
    let lineEndStation: String
    let destinationCode: String
    let destinationName: String
    let destinationOptions: [BusLineDestinationOption]
    let directionFilterMode: BusLineDirectionFilterMode

    var id: String {
        "\(station.id)-\(lineCode)-\(direction)-\(currentStopID ?? station.id)"
    }

    var cacheKey: String {
        id
    }

    var realtimeMonitorKey: String {
        "\(lineCode)-\(direction)"
    }

    var routeBadge: BusRouteBadge {
        BusRouteBadge(
            lineCode: lineCode,
            title: badgeTitle
        )
    }

    var selectedDestination: BusLineDestinationOption {
        destinationOptions.first(where: { $0.code == destinationCode })
            ?? BusLineDestinationOption(
                code: destinationCode,
                name: destinationName,
                timetableTypes: []
            )
    }

    var defaultDestinationOption: BusLineDestinationOption {
        destinationOptions.first(where: {
            normalizedBusStationName($0.name) == normalizedBusStationName(lineEndStation)
        })
            ?? destinationOptions.first
            ?? selectedDestination
    }

    var specialDestinationOption: BusLineDestinationOption? {
        destinationOptions.first(where: {
            normalizedBusStationName($0.name) != normalizedBusStationName(lineEndStation)
        })
    }

    var directionFilterOptions: [BusLineDirectionFilterOption] {
        guard let specialDestinationOption else {
            return []
        }

        return [
            BusLineDirectionFilterOption(
                mode: .all,
                title: "全部"
            ),
            BusLineDirectionFilterOption(
                mode: .special,
                title: "开往 \(specialDestinationOption.name)"
            )
        ]
    }

    var sheetSubtitle: String {
        if directionTitle == "顺时针" || directionTitle == "逆时针" {
            return directionTitle
        }

        if directionTitle.isEmpty || directionTitle == destinationName {
            return "开往 \(destinationName)"
        }

        return "\(directionTitle) · 开往 \(destinationName)"
    }

    func updatingDirectionFilter(
        _ mode: BusLineDirectionFilterMode
    ) -> BusLineDetailSelection {
        let resolvedDestination: BusLineDestinationOption
        switch mode {
        case .all:
            resolvedDestination = defaultDestinationOption
        case .special:
            resolvedDestination = specialDestinationOption ?? defaultDestinationOption
        }

        return BusLineDetailSelection(
            station: station,
            currentStopID: currentStopID,
            lineCode: lineCode,
            lineName: lineName,
            badgeTitle: badgeTitle,
            direction: direction,
            directionTitle: directionTitle,
            lineEndStation: lineEndStation,
            destinationCode: resolvedDestination.code,
            destinationName: resolvedDestination.name,
            destinationOptions: destinationOptions,
            directionFilterMode: mode
        )
    }
}

// MARK: - Route Matching

private let busStationCoordinateMatchThreshold: CLLocationDistance = 60

func resolvedCurrentLineStation(
    for selection: BusLineDetailSelection,
    in lineStations: [BusAPI.LineStation]
) -> BusAPI.LineStation? {
    resolvedCurrentLineStations(for: selection, in: lineStations).first
}

func resolvedCurrentLineStations(
    for selection: BusLineDetailSelection,
    in lineStations: [BusAPI.LineStation]
) -> [BusAPI.LineStation] {
    let sortedLineStations = lineStations.sorted { lhs, rhs in
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }

        return lhs.id < rhs.id
    }

    guard !sortedLineStations.isEmpty else {
        return []
    }

    if let currentStopID = selection.currentStopID {
        let lineStopMatches = sortedLineStations.filter { $0.id == currentStopID }
        if !lineStopMatches.isEmpty {
            return lineStopMatches
        }

        let routeStationMatches = sortedLineStations.filter { $0.station.id == currentStopID }
        if !routeStationMatches.isEmpty {
            return routeStationMatches
        }
    }

    let legacyIDMatches = sortedLineStations.filter { $0.station.id == selection.station.id }
    if !legacyIDMatches.isEmpty {
        return legacyIDMatches
    }

    let normalizedStationName = normalizedBusStationName(selection.station.name)
    let sameNameMatches = sortedLineStations.filter {
        normalizedBusStationName($0.station.name) == normalizedStationName
    }
    if !sameNameMatches.isEmpty {
        return sortLineStationsByDistance(
            sameNameMatches,
            to: selection.station.coordinate
        )
    }

    let nearbyMatches = sortedLineStations.filter {
        busStationDistance(
            from: selection.station.coordinate,
            to: $0.station.location.coordinate
        ) <= busStationCoordinateMatchThreshold
    }
    if !nearbyMatches.isEmpty {
        return sortLineStationsByDistance(
            nearbyMatches,
            to: selection.station.coordinate
        )
    }

    return []
}

func normalizedBusStationName(
    _ name: String
) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func sortLineStationsByDistance(
    _ lineStations: [BusAPI.LineStation],
    to coordinate: CLLocationCoordinate2D
) -> [BusAPI.LineStation] {
    lineStations.sorted { lhs, rhs in
        let lhsDistance = busStationDistance(
            from: coordinate,
            to: lhs.station.location.coordinate
        )
        let rhsDistance = busStationDistance(
            from: coordinate,
            to: rhs.station.location.coordinate
        )

        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }

        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }

        return lhs.id < rhs.id
    }
}

private func busStationDistance(
    from lhs: CLLocationCoordinate2D,
    to rhs: CLLocationCoordinate2D
) -> CLLocationDistance {
    CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
}

func sortedLineStations(
    _ lineStations: [BusAPI.LineStation]
) -> [BusAPI.LineStation] {
    lineStations.sorted { lhs, rhs in
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }

        return lhs.id < rhs.id
    }
}

private func lineStationCodePrefix(
    _ stationCode: String
) -> String {
    stationCode.split(separator: "-").first.map(String.init) ?? stationCode
}

private func matchesDestination(
    _ lineStation: BusAPI.LineStation,
    selection: BusLineDetailSelection
) -> Bool {
    matchesDestination(
        lineStation,
        destination: selection.selectedDestination
    )
}

private func matchesDestination(
    _ lineStation: BusAPI.LineStation,
    destination: BusLineDestinationOption
) -> Bool {
    if lineStationCodePrefix(lineStation.stationCode) == destination.code {
        return true
    }

    return normalizedBusStationName(lineStation.station.name)
        == normalizedBusStationName(destination.name)
}

private func destinationCutoffLineStation(
    for selection: BusLineDetailSelection,
    in lineStations: [BusAPI.LineStation]
) -> BusAPI.LineStation? {
    destinationCutoffLineStation(
        for: selection,
        destination: selection.selectedDestination,
        in: lineStations
    )
}

private func destinationCutoffLineStation(
    for selection: BusLineDetailSelection,
    destination: BusLineDestinationOption,
    in lineStations: [BusAPI.LineStation]
) -> BusAPI.LineStation? {
    let sortedStations = sortedLineStations(lineStations)
    guard !sortedStations.isEmpty else {
        return nil
    }

    let currentIndex = resolvedCurrentLineStation(
        for: selection,
        in: sortedStations
    )?.index ?? sortedStations.first?.index ?? 0

    let futureDestinationStations = sortedStations.filter { lineStation in
        lineStation.index >= currentIndex
            && matchesDestination(lineStation, destination: destination)
    }

    guard !futureDestinationStations.isEmpty else {
        return nil
    }

    return futureDestinationStations.max { lhs, rhs in
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }

        return lhs.id < rhs.id
    }
}

func destinationFilteredLineStations(
    for selection: BusLineDetailSelection,
    in lineStations: [BusAPI.LineStation]
) -> [BusAPI.LineStation] {
    destinationFilteredLineStations(
        for: selection,
        destination: selection.selectedDestination,
        in: lineStations
    )
}

func destinationFilteredLineStations(
    for selection: BusLineDetailSelection,
    destination: BusLineDestinationOption,
    in lineStations: [BusAPI.LineStation]
) -> [BusAPI.LineStation] {
    let sortedStations = sortedLineStations(lineStations)
    guard let cutoffLineStation = destinationCutoffLineStation(
        for: selection,
        destination: destination,
        in: sortedStations
    ) else {
        return sortedStations
    }

    return sortedStations.filter { lineStation in
        lineStation.index <= cutoffLineStation.index
    }
}

func resolvedTimetableTypes(
    for selection: BusLineDetailSelection,
    in lineStations: [BusAPI.LineStation]
) -> Set<String> {
    let allTypes = Set(
        selection.destinationOptions
            .flatMap(\.timetableTypes)
            .filter { !$0.isEmpty }
    )
    let specialTypes = Set(
        (selection.specialDestinationOption?.timetableTypes ?? [])
            .filter { !$0.isEmpty }
    )

    if selection.directionFilterMode == .all {
        guard selection.lineCode == "918484" else {
            return allTypes.isEmpty ? [BusShuttleScheduleType.normal.rawValue] : allTypes
        }

        return allTypes.isEmpty ? [
            BusShuttleScheduleType.outboundNormal.rawValue,
            BusShuttleScheduleType.normal.rawValue,
            BusShuttleScheduleType.normalInbound.rawValue
        ] : allTypes
    }

    guard selection.lineCode == "918484" else {
        return specialTypes
    }

    let sortedStations = sortedLineStations(lineStations)
    guard !sortedStations.isEmpty else {
        return specialTypes
    }

    if let specialDestination = selection.specialDestinationOption,
       let lastStation = sortedStations.last,
       matchesDestination(lastStation, destination: specialDestination) {
        return [BusShuttleScheduleType.normalInbound.rawValue]
    }

    if sortedStations.count >= 2 {
        let secondLastStation = sortedStations[sortedStations.count - 2]
        if let specialDestination = selection.specialDestinationOption,
           matchesDestination(secondLastStation, destination: specialDestination) {
            return [
                BusShuttleScheduleType.outboundNormal.rawValue,
                BusShuttleScheduleType.normal.rawValue
            ]
        }
    }

    return specialTypes
}

func resolvedDisplayedStations(
    for selection: BusLineDetailSelection,
    activeSchedule: BusAPI.TimetableEntry?,
    in lineStations: [BusAPI.LineStation]
) -> [BusAPI.LineStation] {
    let routeDestination: BusLineDestinationOption
    if selection.directionFilterMode == .special,
       let specialDestinationOption = selection.specialDestinationOption {
        routeDestination = specialDestinationOption
    } else if selection.lineCode == "918484",
              activeSchedule?.type == BusShuttleScheduleType.normalInbound.rawValue,
              let specialDestinationOption = selection.specialDestinationOption {
        routeDestination = specialDestinationOption
    } else {
        routeDestination = selection.defaultDestinationOption
    }

    let filteredStations = destinationFilteredLineStations(
        for: selection,
        destination: routeDestination,
        in: lineStations
    )

    guard selection.lineCode == "918484",
          let activeSchedule,
          let scheduleType = BusShuttleScheduleType(rawValue: activeSchedule.type) else {
        return filteredStations
    }

    switch scheduleType {
    case .outboundNormal:
        return filteredStations
    case .normal, .normalInbound:
        return Array(filteredStations.dropFirst())
    }
}
