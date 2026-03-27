//
//  BusLineDetailSheetContent.swift
//  MySJTU
//

import SwiftUI
import UIKit

struct BusLineDetailSheetContent: View {
    private struct ListedStationEntry: Identifiable {
        let index: Int
        let station: BusAPI.LineStation

        var id: Int {
            station.id
        }
    }

    private struct ContentState {
        let data: BusLinePanelData?
        let selectedLineStation: BusAPI.LineStation?
        let displayedStations: [BusAPI.LineStation]
        let selectedDisplayedStationIndex: Int?
        let stationListStartIndex: Int
        let listedStationEntries: [ListedStationEntry]
        let shouldShowCollapsedStationsRow: Bool
        let selectedTimetable: [BusAPI.TimetableEntry]
        let selectedTimetableIDs: [String]
        let comingSchedules: [BusAPI.TimetableEntry]
        let comingScheduleIDs: [String]
        let scheduleTimeTextByIndex: [Int: String]
    }

    let selection: BusLineDetailSelection
    let state: BusLinePanelState
    let onRefresh: () -> Void
    let onSelectDirectionFilter: (BusLineDirectionFilterMode) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showAllStations = false
    @State private var activeSchedule: BusAPI.TimetableEntry?

    var body: some View {
        let content = contentState()

        ScrollView {
            VStack(spacing: 0) {
                destinationSelectionSection
                upcomingScheduleSection(content: content)
                stationListSection(content: content)
            }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            syncActiveSchedule(using: content)
        }
        .onChange(of: selection.id) {
            syncActiveSchedule(
                using: content,
                forceReset: true
            )
        }
        .onChange(of: selection.destinationCode) {
            syncActiveSchedule(
                using: content,
                forceReset: true
            )
        }
        .onChange(of: content.selectedTimetableIDs) {
            syncActiveSchedule(using: content)
        }
        .onChange(of: state.isLoading) {
            syncActiveSchedule(using: content)
        }
    }

    @ViewBuilder
    private var destinationSelectionSection: some View {
        if !selection.directionFilterOptions.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(selection.directionFilterOptions) { option in
                        destinationOptionButton(for: option)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .contentMargins([.leading, .trailing], 20, for: .scrollContent)
        }
    }

    private func destinationOptionButton(
        for option: BusLineDirectionFilterOption
    ) -> some View {
        let isSelected = option.mode == selection.directionFilterMode

        return Button(option.title) {
            guard !isSelected else {
                return
            }

            onSelectDirectionFilter(option.mode)
        }
        .buttonStyle(BusLineDetailDestinationCapsuleStyle(isSelected: isSelected))
    }

    private func upcomingScheduleSection(
        content: ContentState
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("临近出发班次")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding([.leading, .trailing])

            upcomingScheduleContent(content: content)
        }
        .frame(height: 96, alignment: .top)
        .animation(.easeInOut, value: content.selectedTimetableIDs)
        .animation(.easeInOut, value: content.comingScheduleIDs)
    }

    @ViewBuilder
    private func upcomingScheduleContent(
        content: ContentState
    ) -> some View {
        if let errorMessage = state.errorMessage, content.data == nil {
            VStack {
                BusSheetStatusBanner(
                    title: "线路详情加载失败",
                    message: errorMessage,
                    isLoading: false,
                    onRefresh: onRefresh
                )
                .padding([.leading, .trailing, .bottom])
                .padding([.top], 8)
            }
        } else if content.data != nil, !content.comingSchedules.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(content.comingSchedules) { schedule in
                        BusLineScheduleCard(
                            schedule: schedule,
                            isSelected: schedule.id == activeSchedule?.id,
                            subtitle: BusScheduleClock.relativeDescription(for: schedule),
                            colorScheme: colorScheme
                        ) {
                            guard activeSchedule != schedule else {
                                return
                            }

                            activeSchedule = schedule
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .scrollIndicators(.hidden)
            .contentMargins([.leading, .trailing], 14, for: .scrollContent)
        } else if state.isLoading {
            VStack {
                ProgressView()
                    .padding()
            }
            .frame(maxWidth: .infinity)
            .padding([.leading, .trailing, .bottom])
        } else if content.data != nil {
            VStack {
                Text("今日运营已结束")
                    .padding()
            }
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.clear)
                    .glassEffect(in: .rect(cornerRadius: 26, style: .continuous))
            }
            .padding([.leading, .trailing, .bottom])
            .padding([.top], 8)
        }
    }

    private func stationListSection(
        content: ContentState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("停靠站")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if !content.displayedStations.isEmpty {
                    Button {
                        showAllStations.toggle()
                    } label: {
                        showAllStations ? Text("收起") : Text("更多")
                    }
                    .tint(.blue)
                }
            }

            VStack(spacing: 0) {
                if let errorMessage = state.errorMessage, content.data == nil {
                    BusSheetStatusBanner(
                        title: "线路详情加载失败",
                        message: errorMessage,
                        isLoading: false,
                        onRefresh: onRefresh
                    )
                    .padding()
                } else if content.displayedStations.isEmpty {
                    ProgressView()
                        .padding()
                } else {
                    if content.shouldShowCollapsedStationsRow {
                        CollapsedStationsRow(hiddenCount: content.stationListStartIndex - 1)
                    }

                    ForEach(content.listedStationEntries) { entry in
                        BusLineDetailStationRow(
                            station: entry.station,
                            index: entry.index,
                            totalCount: content.displayedStations.count,
                            currentIndex: content.stationListStartIndex,
                            isSelected: entry.station.id == content.selectedLineStation?.id,
                            timeText: content.scheduleTimeTextByIndex[entry.index]
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.clear)
                    .glassEffect(in: .rect(cornerRadius: 26, style: .continuous))
            }
            .animation(.easeInOut, value: showAllStations)
        }
        .animation(.easeInOut, value: selection.id)
        .animation(
            .easeInOut,
            value: content.displayedStations.map(\.id)
        )
        .padding([.leading, .trailing, .bottom])
    }

    private func syncActiveSchedule(
        using content: ContentState,
        forceReset: Bool = false
    ) {
        guard !content.selectedTimetable.isEmpty else {
            guard activeSchedule != nil else {
                return
            }

            activeSchedule = nil
            return
        }

        guard
            forceReset
            || content.selectedTimetable.first(where: { $0.id == activeSchedule?.id }) == nil
        else {
            return
        }

        guard let nextActiveSchedule = content.comingSchedules.first ?? content.selectedTimetable.first else {
            return
        }

        guard activeSchedule != nextActiveSchedule else {
            return
        }

        activeSchedule = nextActiveSchedule
    }

    private func isUpcomingSchedule(
        _ schedule: BusAPI.TimetableEntry
    ) -> Bool {
        guard let scheduleDate = schedule.scheduledDate else {
            return false
        }

        return scheduleDate.timeIntervalSinceNow >= -60
    }

    private func contentState() -> ContentState {
        let data = state.cachedData
        let lineStations = data?.lineStations ?? []
        let selectedLineStation = resolvedCurrentLineStation(
            for: selection,
            in: lineStations
        )
        let displayedStations = resolvedDisplayedStations(
            for: selection,
            activeSchedule: activeSchedule,
            in: lineStations
        )
        let selectedDisplayedStationIndex = selectedLineStation.flatMap { selectedLineStation in
            displayedStations.firstIndex { $0.id == selectedLineStation.id }
        }
        let stationListStartIndex = selectedDisplayedStationIndex ?? 0
        let lowerBound = showAllStations ? 0 : max(0, stationListStartIndex - 1)
        let listedStationEntries = displayedStations
            .enumerated()
            .dropFirst(lowerBound)
            .map { entry in
                ListedStationEntry(
                    index: entry.offset,
                    station: entry.element
                )
            }

        let selectedTimetable: [BusAPI.TimetableEntry]
        if let selectedLineStation {
            let timetable = data?.timetablesByStopID[selectedLineStation.id] ?? []
            let supportedTypes = resolvedTimetableTypes(
                for: selection,
                in: lineStations
            )

            if supportedTypes.isEmpty {
                selectedTimetable = timetable
            } else {
                let filteredTimetable = timetable.filter { entry in
                    supportedTypes.contains(entry.type)
                }
                selectedTimetable = filteredTimetable.isEmpty ? timetable : filteredTimetable
            }
        } else {
            selectedTimetable = []
        }

        let comingSchedules = selectedTimetable.filter(isUpcomingSchedule)

        return ContentState(
            data: data,
            selectedLineStation: selectedLineStation,
            displayedStations: displayedStations,
            selectedDisplayedStationIndex: selectedDisplayedStationIndex,
            stationListStartIndex: stationListStartIndex,
            listedStationEntries: listedStationEntries,
            shouldShowCollapsedStationsRow: !showAllStations && stationListStartIndex > 1,
            selectedTimetable: selectedTimetable,
            selectedTimetableIDs: selectedTimetable.map(\.id),
            comingSchedules: comingSchedules,
            comingScheduleIDs: comingSchedules.map(\.id),
            scheduleTimeTextByIndex: scheduleTimeTextByIndex(
                activeSchedule: activeSchedule,
                selectedDisplayedStationIndex: selectedDisplayedStationIndex,
                displayedStations: displayedStations
            )
        )
    }

    private func scheduleTimeTextByIndex(
        activeSchedule: BusAPI.TimetableEntry?,
        selectedDisplayedStationIndex: Int?,
        displayedStations: [BusAPI.LineStation]
    ) -> [Int: String] {
        guard
            let activeSchedule,
            let selectedDisplayedStationIndex,
            let scheduleDate = activeSchedule.scheduledDate,
            selectedDisplayedStationIndex < displayedStations.count
        else {
            return [:]
        }

        var cumulativeMinutes: [Int] = []
        cumulativeMinutes.reserveCapacity(displayedStations.count)

        var runningMinutes = 0
        for station in displayedStations {
            runningMinutes += station.time
            cumulativeMinutes.append(runningMinutes)
        }

        let routeStartDate = scheduleDate.addingTimeInterval(
            -Double(cumulativeMinutes[selectedDisplayedStationIndex] * 60)
        )
        var result: [Int: String] = [:]
        result.reserveCapacity(displayedStations.count - selectedDisplayedStationIndex)

        for index in selectedDisplayedStationIndex..<displayedStations.count {
            let stationDate = routeStartDate.addingTimeInterval(
                Double(cumulativeMinutes[index] * 60)
            )
            result[index] = BusScheduleClock.formatTime(stationDate)
        }

        return result
    }
}

private struct BusLineDetailDestinationCapsuleStyle: ButtonStyle {
    let isSelected: Bool

    private var routeTint: Color {
        BusRouteStyle.campusShuttle.tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? .white : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? routeTint.opacity(configuration.isPressed ? 0.88 : 1) : .clear)
                    .background {
                        if !isSelected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.clear)
                                .glassEffect(in: .rect(cornerRadius: 18, style: .continuous))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? Color.white.opacity(0.18) : routeTint.opacity(0.14),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: isSelected ? routeTint.opacity(0.2) : .clear,
                radius: 12,
                y: 6
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct BusLineScheduleCard: View {
    let schedule: BusAPI.TimetableEntry
    let isSelected: Bool
    let subtitle: String?
    let colorScheme: ColorScheme
    let onTap: () -> Void

    private var timeLabelColor: Color {
        isSelected ? Color(UIColor.label) : Color(UIColor.secondaryLabel)
    }

    private var subtitleColor: Color {
        isSelected ? Color(UIColor.secondaryLabel) : Color(UIColor.tertiaryLabel)
    }

    var body: some View {
        VStack {
            Button(action: onTap) {
                VStack(spacing: 0) {
                    timeLabel

                    Text(subtitle ?? BusScheduleClock.dayDescription(for: schedule.executionDate))
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                }
                .padding([.leading, .trailing])
                .padding([.top, .bottom], 8)
            }
            .buttonStyle(.plain)
        }
        .background(
            isSelected
                ? Color(UIColor.secondarySystemGroupedBackground)
                : Color(UIColor.tertiarySystemGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .if(isSelected && colorScheme == .light) {
            $0.shadow(color: Color(UIColor.systemGray3), radius: 1, x: 0, y: 1)
        }
        .padding([.top], 8)
        .padding([.bottom])
        .id(schedule.id)
    }

    private var timeLabel: some View {
        Text(schedule.time)
            .fontWeight(isSelected ? .semibold : .medium)
            .foregroundStyle(timeLabelColor)
            .monospacedDigit()
    }
}

private struct TimelineLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        return path
    }
}

private struct CollapsedStationsRow: View {
    let hiddenCount: Int

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                TimelineLineShape()
                    .stroke(style: StrokeStyle(lineWidth: 4, dash: [5]))
                    .fill(Color(UIColor.systemGray2))
                    .frame(width: 4)
                    .offset(x: 2)
            }
            .frame(width: 36, height: 24)

            Text("前\(hiddenCount)站")
                .foregroundStyle(Color(UIColor.systemGray2))

            Spacer()
        }
        .padding([.leading, .trailing])
    }
}

private struct BusLineDetailStationRow: View {
    let station: BusAPI.LineStation
    let index: Int
    let totalCount: Int
    let currentIndex: Int
    let isSelected: Bool
    let timeText: String?

    private var isPast: Bool {
        index < currentIndex
    }

    var body: some View {
        HStack(spacing: 0) {
            BusStationTimeline(
                index: index,
                totalCount: totalCount,
                currentIndex: currentIndex,
                isSelected: isSelected
            )
            .frame(width: 36, height: 48)

            Text(station.station.name)
                .fontWeight(isSelected ? .semibold : .regular)
                .if(isPast) {
                    $0.foregroundStyle(Color(UIColor.systemGray2))
                }

            Spacer()

            if let timeText {
                Text(timeText)
                    .font(.callout)
                    .monospacedDigit()
            }
        }
        .padding([.leading, .trailing])
    }
}

private struct BusStationTimeline: View {
    let index: Int
    let totalCount: Int
    let currentIndex: Int
    let isSelected: Bool

    private let layout = Layout()
    private let palette = Palette()

    private var appearance: Appearance {
        Appearance(
            index: index,
            totalCount: totalCount,
            currentIndex: currentIndex,
            isSelected: isSelected,
            palette: palette
        )
    }

    var body: some View {
        ZStack(alignment: .center) {
            ForEach(SegmentPosition.allCases, id: \.self) { position in
                timelineSegment(at: position)
            }
            timelineNode
        }
    }

    @ViewBuilder
    private func timelineSegment(at position: SegmentPosition) -> some View {
        if let color = appearance.segmentColor(at: position) {
            Rectangle()
                .fill(color)
                .frame(width: layout.lineWidth, height: layout.segmentHeight)
                .position(x: layout.centerX, y: position.y)
        }
    }

    private var timelineNode: some View {
        let nodeStyle = appearance.nodeStyle

        return Circle()
            .fill(nodeStyle.fillColor(using: palette))
            .stroke(nodeStyle.strokeColor(using: palette), lineWidth: nodeStyle.strokeWidth(using: layout))
            .frame(
                width: nodeStyle.diameter(using: layout),
                height: nodeStyle.diameter(using: layout)
            )
            .position(x: layout.centerX, y: layout.centerY)
    }
}

private extension BusStationTimeline {
    struct Layout {
        let lineWidth: CGFloat = 4
        let segmentHeight: CGFloat = 24
        let smallNodeSize: CGFloat = 8
        let largeNodeSize: CGFloat = 12
        let centerX: CGFloat = 18
        let centerY: CGFloat = 24
    }

    struct Palette {
        let past = Color(UIColor.systemGray2)
        let active = BusRouteStyle.campusShuttle.tint
        let background = Color(UIColor.systemBackground)
    }

    struct Placement {
        let isFirst: Bool
        let isLast: Bool

        init(index: Int, totalCount: Int) {
            isFirst = index == 0
            isLast = index == totalCount - 1
        }
    }

    enum Progress {
        case past
        case current
        case upcoming

        init(index: Int, currentIndex: Int) {
            if index < currentIndex {
                self = .past
            } else if index == currentIndex {
                self = .current
            } else {
                self = .upcoming
            }
        }
    }

    enum SegmentPosition: CaseIterable {
        case top
        case bottom

        var y: CGFloat {
            switch self {
            case .top:
                12
            case .bottom:
                36
            }
        }
    }

    enum NodeStyle {
        case selected
        case filled(Color)
        case outlined(Color)

        func fillColor(using palette: Palette) -> Color {
            switch self {
            case .selected, .outlined:
                palette.background
            case .filled(let color):
                color
            }
        }

        func strokeColor(using palette: Palette) -> Color {
            switch self {
            case .selected:
                palette.active
            case .filled:
                palette.background
            case .outlined(let color):
                color
            }
        }

        func strokeWidth(using layout: Layout) -> CGFloat {
            switch self {
            case .selected:
                layout.lineWidth
            case .filled:
                0.5
            case .outlined:
                2
            }
        }

        func diameter(using layout: Layout) -> CGFloat {
            switch self {
            case .outlined:
                layout.smallNodeSize
            case .selected, .filled:
                layout.largeNodeSize
            }
        }
    }

    struct Appearance {
        let topSegmentColor: Color?
        let bottomSegmentColor: Color?
        let nodeStyle: NodeStyle

        init(index: Int, totalCount: Int, currentIndex: Int, isSelected: Bool, palette: Palette) {
            let placement = Placement(index: index, totalCount: totalCount)
            let progress = Progress(index: index, currentIndex: currentIndex)

            topSegmentColor = Self.topSegmentColor(for: placement, progress: progress, palette: palette)
            bottomSegmentColor = Self.bottomSegmentColor(for: placement, progress: progress, palette: palette)
            nodeStyle = Self.nodeStyle(for: placement, progress: progress, isSelected: isSelected, palette: palette)
        }

        func segmentColor(at position: SegmentPosition) -> Color? {
            switch position {
            case .top:
                topSegmentColor
            case .bottom:
                bottomSegmentColor
            }
        }

        private static func topSegmentColor(for placement: Placement, progress: Progress, palette: Palette) -> Color? {
            guard !placement.isFirst else {
                return nil
            }

            switch progress {
            case .past, .current:
                return palette.past
            case .upcoming:
                return palette.active
            }
        }

        private static func bottomSegmentColor(for placement: Placement, progress: Progress, palette: Palette) -> Color? {
            guard !placement.isLast else {
                return nil
            }

            switch progress {
            case .past:
                return palette.past
            case .current, .upcoming:
                return palette.active
            }
        }

        private static func nodeStyle(for placement: Placement, progress: Progress, isSelected: Bool, palette: Palette) -> NodeStyle {
            switch progress {
            case .past:
                return placement.isFirst ? .filled(palette.past) : .outlined(palette.past)
            case .current, .upcoming:
                if isSelected {
                    return .selected
                }

                return placement.isFirst || placement.isLast ? .filled(palette.active) : .outlined(palette.active)
            }
        }
    }
}
