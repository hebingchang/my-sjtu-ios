//
//  BusMapViewModel.swift
//  MySJTU
//

import Combine
import Foundation
import SwiftUI

// MARK: - Panel State

struct BusStationPanelData {
    let cards: [BusDepartureCard]
    let fetchedAt: Date
}

struct BusLinePanelData {
    let route: BusAPI.Route?
    let lineStations: [BusAPI.LineStation]
    let timetablesByStopID: [Int: [BusAPI.TimetableEntry]]
    let fetchedAt: Date
}

enum BusStationPanelState {
    case idle
    case loading(BusStationPanelData?)
    case loaded(BusStationPanelData)
    case failed(String, BusStationPanelData?)

    var cachedData: BusStationPanelData? {
        switch self {
        case .idle:
            return nil
        case .loading(let data), .failed(_, let data):
            return data
        case .loaded(let data):
            return data
        }
    }

    var errorMessage: String? {
        if case .failed(let message, _) = self {
            return message
        }

        return nil
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }

        return false
    }
}

enum BusLinePanelState {
    case idle
    case loading(BusLinePanelData?)
    case loaded(BusLinePanelData)
    case failed(String, BusLinePanelData?)

    var cachedData: BusLinePanelData? {
        switch self {
        case .idle:
            return nil
        case .loading(let data), .failed(_, let data):
            return data
        case .loaded(let data):
            return data
        }
    }

    var errorMessage: String? {
        if case .failed(let message, _) = self {
            return message
        }

        return nil
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }

        return false
    }
}

private func timetableSort(
    lhs: BusAPI.TimetableEntry,
    rhs: BusAPI.TimetableEntry
) -> Bool {
    if lhs.executionDate != rhs.executionDate {
        return lhs.executionDate < rhs.executionDate
    }

    if lhs.timeInt != rhs.timeInt {
        return lhs.timeInt < rhs.timeInt
    }

    return lhs.type < rhs.type
}

private func realtimeVehicleSort(
    lhs: BusAPI.RealtimeVehicle,
    rhs: BusAPI.RealtimeVehicle
) -> Bool {
    if lhs.vehicleCode != rhs.vehicleCode {
        return lhs.vehicleCode < rhs.vehicleCode
    }

    return lhs.updatedAt < rhs.updatedAt
}

// MARK: - View Model

@MainActor
final class BusMapViewModel: ObservableObject {
    private static let panelRefreshInterval: TimeInterval = 45
    private static let realtimeReconnectDelayNanoseconds: UInt64 = 2_000_000_000

    @Published private(set) var stations: [BusAPI.Station] = []
    @Published private(set) var isLoadingStations: Bool = false
    @Published private(set) var stationLoadError: String?
    @Published private var panels: [Int: BusStationPanelState] = [:]
    @Published private var linePanels: [String: BusLinePanelState] = [:]
    @Published private(set) var activeRealtimeVehicles: [BusAPI.RealtimeVehicle] = []
    @Published private(set) var activeRealtimeMonitorKey: String?

    private var panelTasks: [Int: Task<Void, Never>] = [:]
    private var linePanelTasks: [String: Task<BusLinePanelData?, Never>] = [:]
    private var realtimeMonitorTask: Task<Void, Never>?
    private var realtimeWebSocketTask: URLSessionWebSocketTask?

    deinit {
        panelTasks.values.forEach { $0.cancel() }
        linePanelTasks.values.forEach { $0.cancel() }
        realtimeMonitorTask?.cancel()
        realtimeWebSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    func loadStationsIfNeeded() async {
        guard stations.isEmpty else {
            return
        }

        await reloadStations()
    }

    func reloadStations() async {
        guard !isLoadingStations else {
            return
        }

        isLoadingStations = true
        stationLoadError = nil
        defer {
            isLoadingStations = false
        }

        do {
            stations = try await BusAPI.fetchStations()
        } catch {
            stationLoadError = error.localizedDescription
        }
    }

    func panelState(for station: BusAPI.Station) -> BusStationPanelState {
        panels[station.id] ?? .idle
    }

    func lineDetailState(
        for selection: BusLineDetailSelection
    ) -> BusLinePanelState {
        linePanels[selection.cacheKey] ?? .idle
    }

    func realtimeVehicles(
        for selection: BusLineDetailSelection
    ) -> [BusAPI.RealtimeVehicle] {
        guard activeRealtimeMonitorKey == selection.realtimeMonitorKey else {
            return []
        }

        return activeRealtimeVehicles
    }

    func activateRealtimeMonitor(
        for selection: BusLineDetailSelection
    ) {
        let previousMonitorKey = activeRealtimeMonitorKey

        guard
            previousMonitorKey != selection.realtimeMonitorKey
            || realtimeMonitorTask == nil
        else {
            return
        }

        stopRealtimeMonitor(clearVehicles: previousMonitorKey != selection.realtimeMonitorKey)

        activeRealtimeMonitorKey = selection.realtimeMonitorKey
        if previousMonitorKey != selection.realtimeMonitorKey {
            activeRealtimeVehicles = []
        }

        guard let url = BusAPI.realtimeMonitorURL(
            lineCode: selection.lineCode,
            direction: selection.direction
        ) else {
            return
        }

        realtimeMonitorTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.runRealtimeMonitor(
                url: url,
                selection: selection
            )
        }
    }

    func deactivateRealtimeMonitor() {
        stopRealtimeMonitor(clearVehicles: true)
    }

    func loadPanel(
        for station: BusAPI.Station,
        forceRefresh: Bool = false
    ) {
        if !forceRefresh,
           let state = panels[station.id] {
            if state.isLoading {
                return
            }

            if let cached = state.cachedData,
               Date.now.timeIntervalSince(cached.fetchedAt) < Self.panelRefreshInterval {
                return
            }
        }

        let cachedData = panels[station.id]?.cachedData
        panels[station.id] = .loading(cachedData)

        panelTasks[station.id]?.cancel()
        panelTasks[station.id] = Task {
            do {
                let result = try await BusAPI.fetchNextDepartures(stationID: station.id)
                guard !Task.isCancelled else {
                    return
                }

                let data = BusStationPanelData(
                    cards: BusDepartureCard.makeCards(
                        for: result.station,
                        departures: result.departures
                    ),
                    fetchedAt: Date.now
                )
                panels[station.id] = .loaded(data)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                panels[station.id] = .failed(
                    error.localizedDescription,
                    cachedData
                )
            }

            panelTasks[station.id] = nil
        }
    }

    func loadLineDetail(
        for selection: BusLineDetailSelection,
        forceRefresh: Bool = false
    ) async -> BusLinePanelData? {
        let key = selection.cacheKey

        if !forceRefresh,
           let state = linePanels[key] {
            if let cached = state.cachedData,
               Date.now.timeIntervalSince(cached.fetchedAt) < Self.panelRefreshInterval {
                return cached
            }

            if state.isLoading,
               let existingTask = linePanelTasks[key] {
                return await existingTask.value
            }
        }

        let cachedData = linePanels[key]?.cachedData
        linePanels[key] = .loading(cachedData)

        linePanelTasks[key]?.cancel()
        let task = Task<BusLinePanelData?, Never> { [selection, cachedData] in
            do {
                let route = try? await BusAPI.fetchRoute(
                    lineCode: selection.lineCode,
                    direction: selection.direction
                )
                let lineStations = sortedLineStations(
                    (try? await BusAPI.fetchLineStations(
                        lineCode: selection.lineCode,
                        direction: selection.direction
                    )) ?? []
                )
                let stopIDs = Self.stopIDs(
                    for: selection,
                    in: lineStations
                )
                let timetablesByStopID = try await Self.loadTimetables(
                    lineCode: selection.lineCode,
                    direction: selection.direction,
                    stopIDs: stopIDs
                )

                let data = BusLinePanelData(
                    route: route,
                    lineStations: lineStations,
                    timetablesByStopID: timetablesByStopID,
                    fetchedAt: Date.now
                )
                guard !Task.isCancelled else {
                    return cachedData
                }

                await MainActor.run {
                    self.linePanels[key] = .loaded(data)
                    self.linePanelTasks[key] = nil
                }

                return data
            } catch {
                guard !Task.isCancelled else {
                    return cachedData
                }

                await MainActor.run {
                    self.linePanels[key] = .failed(
                        error.localizedDescription,
                        cachedData
                    )
                    self.linePanelTasks[key] = nil
                }

                return cachedData
            }
        }

        linePanelTasks[key] = task
        return await task.value
    }

    private static func stopIDs(
        for selection: BusLineDetailSelection,
        in lineStations: [BusAPI.LineStation]
    ) -> [Int] {
        Array(
            Set(
                resolvedCurrentLineStations(for: selection, in: lineStations).map(\.id)
            )
        )
        .sorted()
    }

    private static func loadTimetables(
        lineCode: String,
        direction: Int,
        stopIDs: [Int]
    ) async throws -> [Int: [BusAPI.TimetableEntry]] {
        guard !stopIDs.isEmpty else {
            return [:]
        }

        var timetablesByStopID: [Int: [BusAPI.TimetableEntry]] = [:]

        for stopID in stopIDs {
            let entries = try await BusAPI.fetchTimetable(
                lineCode: lineCode,
                direction: direction,
                stationID: stopID
            )
            timetablesByStopID[stopID] = entries.sorted(by: timetableSort)
        }

        return timetablesByStopID
    }

    private func stopRealtimeMonitor(
        clearVehicles: Bool
    ) {
        realtimeMonitorTask?.cancel()
        realtimeMonitorTask = nil

        realtimeWebSocketTask?.cancel(with: .goingAway, reason: nil)
        realtimeWebSocketTask = nil
        activeRealtimeMonitorKey = nil

        guard clearVehicles, !activeRealtimeVehicles.isEmpty else {
            return
        }

        activeRealtimeVehicles = []
    }

    private func runRealtimeMonitor(
        url: URL,
        selection: BusLineDetailSelection
    ) async {
        let realtimeMonitorKey = selection.realtimeMonitorKey

        while !Task.isCancelled {
            guard activeRealtimeMonitorKey == realtimeMonitorKey else {
                return
            }

            let socket = URLSession.shared.webSocketTask(with: url)
            realtimeWebSocketTask = socket
            socket.resume()

            do {
                try await receiveRealtimeMessages(
                    from: socket,
                    selection: selection
                )
            } catch {
                guard !Task.isCancelled else {
                    break
                }
            }

            socket.cancel(with: .goingAway, reason: nil)
            if let currentSocket = realtimeWebSocketTask,
               currentSocket === socket {
                realtimeWebSocketTask = nil
            }

            guard
                !Task.isCancelled,
                activeRealtimeMonitorKey == realtimeMonitorKey
            else {
                break
            }

            try? await Task.sleep(
                nanoseconds: Self.realtimeReconnectDelayNanoseconds
            )
        }
    }

    private func receiveRealtimeMessages(
        from socket: URLSessionWebSocketTask,
        selection: BusLineDetailSelection
    ) async throws {
        while !Task.isCancelled {
            let message = try await socket.receive()
            let decodedVehicles = try realtimeVehicles(
                from: message,
                direction: selection.direction
            )

            guard activeRealtimeMonitorKey == selection.realtimeMonitorKey else {
                return
            }

            withAnimation(.easeInOut(duration: 0.9)) {
                activeRealtimeVehicles = decodedVehicles
            }
        }
    }

    private func realtimeVehicles(
        from message: URLSessionWebSocketTask.Message,
        direction: Int
    ) throws -> [BusAPI.RealtimeVehicle] {
        let payload: Data

        switch message {
        case .data(let data):
            payload = data
        case .string(let text):
            guard let encodedData = text.data(using: .utf8) else {
                return []
            }
            payload = encodedData
        @unknown default:
            return []
        }

        return normalizedRealtimeVehicles(
            try BusAPI.decodeRealtimeVehicles(from: payload),
            direction: direction
        )
    }

    private func normalizedRealtimeVehicles(
        _ vehicles: [BusAPI.RealtimeVehicle],
        direction: Int
    ) -> [BusAPI.RealtimeVehicle] {
        var latestVehicleByCode: [String: BusAPI.RealtimeVehicle] = [:]

        for vehicle in vehicles where vehicle.direction == direction {
            if let existingVehicle = latestVehicleByCode[vehicle.vehicleCode],
               existingVehicle.updatedAt >= vehicle.updatedAt {
                continue
            }

            latestVehicleByCode[vehicle.vehicleCode] = vehicle
        }

        return latestVehicleByCode.values.sorted(by: realtimeVehicleSort)
    }
}
