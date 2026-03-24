//
//  SelfStudyClassroomView.swift
//  MySJTU
//
//  Created by boar on 2026/03/24.
//

import SwiftUI

private enum SelfStudySectionFilter: Hashable {
    case current
    case specific(Int)
}

private enum SelfStudyRoomAvailability: Equatable {
    case free
    case selfStudy
    case occupied(SelfStudyClassroomAPI.RoomCourse?)
    case closed
}

private struct SelfStudyRoomDisplay: Identifiable {
    let room: SelfStudyClassroomAPI.Room
    let availability: SelfStudyRoomAvailability

    var id: Int {
        room.id
    }
}

private struct SelfStudyFloorDisplay: Identifiable {
    let floor: SelfStudyClassroomAPI.Floor
    let freeCount: Int
    let rooms: [SelfStudyRoomDisplay]

    var id: Int {
        floor.id
    }
}

private struct SelfStudyDisplaySnapshot {
    let floors: [SelfStudyFloorDisplay]
    private let closedSectionsByCode: [String: Set<Int>]
    private let closedSectionsByName: [String: Set<Int>]

    init(
        floors: [SelfStudyFloorDisplay],
        closedSectionsByCode: [String: Set<Int>],
        closedSectionsByName: [String: Set<Int>]
    ) {
        self.floors = floors
        self.closedSectionsByCode = closedSectionsByCode
        self.closedSectionsByName = closedSectionsByName
    }

    func closedSections(for room: SelfStudyClassroomAPI.Room) -> Set<Int> {
        if let sections = closedSectionsByCode[room.roomCode.uppercased()] {
            return sections
        }

        if let sections = closedSectionsByName[room.name] {
            return sections
        }

        return []
    }
}

struct SelfStudyClassroomView: View {
    private let minimumInitialLoadingDuration: Duration = .milliseconds(600)

    @State private var loadingInitialData: Bool = true
    @State private var loadingUsageData: Bool = false
    @State private var campuses: [SelfStudyClassroomAPI.Campus] = []
    @State private var sections: [SelfStudyClassroomAPI.SectionTime] = []
    @State private var selectedCampusID: Int?
    @State private var selectedBuildingID: Int?
    @State private var selectedSectionFilter: SelfStudySectionFilter = .current
    @State private var onlyShowFreeRooms: Bool = true
    @State private var searchText: String = ""
    @State private var floors: [SelfStudyClassroomAPI.Floor] = []
    @State private var closedRooms: [SelfStudyClassroomAPI.ClosedRoom] = []
    @State private var serverCurrentSectionIndex: Int?
    @State private var loadErrorMessage: String?
    @State private var initialLoadingStartedAt: ContinuousClock.Instant?
    @State private var loadingSessionID: Int = 0
    @State private var latestSnapshotRequestID: Int = 0

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.systemGroupedBackground,
                Color.secondarySystemGroupedBackground.opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var selectedCampus: SelfStudyClassroomAPI.Campus? {
        guard let selectedCampusID else {
            return campuses.first
        }
        return campuses.first { $0.id == selectedCampusID } ?? campuses.first
    }

    private var selectedBuilding: SelfStudyClassroomAPI.Building? {
        guard let selectedBuildingID else {
            return selectedCampus?.buildings.first
        }
        return selectedCampus?.buildings.first { $0.id == selectedBuildingID } ?? selectedCampus?.buildings.first
    }

    private var effectiveCurrentSectionIndex: Int? {
        if let localReferenceSectionIndex = sections.referenceSectionIndex() {
            return localReferenceSectionIndex
        }

        if sections.isEmpty,
           let serverCurrentSectionIndex {
            return serverCurrentSectionIndex
        }

        return nil
    }

    private var activeSectionIndex: Int? {
        switch selectedSectionFilter {
        case .current:
            return effectiveCurrentSectionIndex
        case .specific(let section):
            return section
        }
    }

    private var activeSection: SelfStudyClassroomAPI.SectionTime? {
        guard let activeSectionIndex else {
            return nil
        }
        return sections.first { $0.sectionIndex == activeSectionIndex }
    }

    private var currentDisplaySnapshot: SelfStudyDisplaySnapshot {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activeSectionIndex = activeSectionIndex
        let totalSectionCount = sections.count
        let closedSectionsByCode = closedRooms.reduce(into: [String: Set<Int>]()) { result, room in
            result[room.roomCode.uppercased()] = room.closedSections
        }
        let closedSectionsByName = closedRooms.reduce(into: [String: Set<Int>]()) { result, room in
            result[room.roomName] = room.closedSections
        }

        func closedSections(for room: SelfStudyClassroomAPI.Room) -> Set<Int> {
            if let sections = closedSectionsByCode[room.roomCode.uppercased()] {
                return sections
            }

            if let sections = closedSectionsByName[room.name] {
                return sections
            }

            return []
        }

        func availability(for room: SelfStudyClassroomAPI.Room) -> SelfStudyRoomAvailability {
            let closedSections = closedSections(for: room)

            guard let activeSectionIndex else {
                if !closedSections.isEmpty && closedSections.count >= totalSectionCount {
                    return .closed
                }
                return room.isSelfStudyRoom ? .selfStudy : .free
            }

            if closedSections.contains(activeSectionIndex) {
                return .closed
            }

            let course = room.courses.first {
                $0.startSection <= activeSectionIndex && $0.endSection >= activeSectionIndex
            }
            if course != nil {
                return .occupied(course)
            }

            return room.isSelfStudyRoom ? .selfStudy : .free
        }

        let floorDisplays = floors.compactMap { floor -> SelfStudyFloorDisplay? in
            let roomDisplays = floor.rooms.map { room in
                SelfStudyRoomDisplay(
                    room: room,
                    availability: availability(for: room)
                )
            }
            let freeCount = roomDisplays.reduce(into: 0) { result, roomDisplay in
                if isFreeLike(roomDisplay.availability) {
                    result += 1
                }
            }
            let filteredRooms = roomDisplays
                .filter { roomDisplay in
                    if !keyword.isEmpty,
                       !roomDisplay.room.name.localizedCaseInsensitiveContains(keyword) {
                        return false
                    }

                    if onlyShowFreeRooms {
                        return isFreeLike(roomDisplay.availability)
                    }

                    return true
                }
                .sorted { lhs, rhs in
                    let leftOrder = availabilityOrder(lhs.availability)
                    let rightOrder = availabilityOrder(rhs.availability)

                    if leftOrder != rightOrder {
                        return leftOrder < rightOrder
                    }

                    if lhs.room.indexNum != rhs.room.indexNum {
                        return (lhs.room.indexNum ?? .max) < (rhs.room.indexNum ?? .max)
                    }

                    return lhs.room.name < rhs.room.name
                }

            guard !filteredRooms.isEmpty else {
                return nil
            }

            return SelfStudyFloorDisplay(
                floor: floor,
                freeCount: freeCount,
                rooms: filteredRooms
            )
        }

        return SelfStudyDisplaySnapshot(
            floors: floorDisplays,
            closedSectionsByCode: closedSectionsByCode,
            closedSectionsByName: closedSectionsByName
        )
    }

    var body: some View {
        ZStack {
            backgroundGradient

            if loadingInitialData {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载教室数据...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                let displaySnapshot = loadingUsageData ? nil : currentDisplaySnapshot

                List {
                    querySection
                    if loadingUsageData {
                        loadingSection
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 6)),
                                    removal: .opacity
                                )
                            )
                    } else {
                        resultSection(displaySnapshot: displaySnapshot ?? currentDisplaySnapshot)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 8)),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .refreshable {
                    await loadBuildingSnapshot()
                }
                .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: loadingUsageData)
                .animation(
                    .snappy(duration: 0.3, extraBounce: 0.02),
                    value: displaySnapshot?.floors.count ?? 0
                )
                .transition(.opacity)
            }
        }
        .navigationTitle("自习教室")
        .searchable(
            text: $searchText,
            prompt: "搜索教室名称"
        )
        .task {
            guard loadingInitialData else {
                return
            }
            await loadInitialData()
        }
        .onChange(of: selectedCampusID) {
            syncSelectedBuildingWithCampus()
        }
        .onChange(of: selectedBuildingID) {
            guard !loadingInitialData else {
                return
            }

            Task {
                await loadBuildingSnapshot()
            }
        }
    }

    private var querySection: some View {
        Section("查询条件") {
            Picker("校区", selection: $selectedCampusID) {
                ForEach(campuses) { campus in
                    Text(campus.name).tag(Optional(campus.id))
                }
            }
            .pickerStyle(.menu)

            Picker("教学楼", selection: $selectedBuildingID) {
                ForEach(selectedCampus?.buildings ?? []) { building in
                    Text(building.name).tag(Optional(building.id))
                }
            }
            .pickerStyle(.menu)

            Picker("查看时段", selection: $selectedSectionFilter) {
                Text("当前时段").tag(SelfStudySectionFilter.current)

                ForEach(sections) { section in
                    Text("第\(section.sectionIndex)节 \(section.startTime)-\(section.endTime)")
                        .tag(SelfStudySectionFilter.specific(section.sectionIndex))
                }
            }
            .pickerStyle(.menu)

            Toggle("只看空闲教室", isOn: $onlyShowFreeRooms)

            if let activeSection {
                LabeledContent("参考节次") {
                    Text("第\(activeSection.sectionIndex)节")
                }
            }

            if let loadErrorMessage, !loadErrorMessage.isEmpty {
                Text(loadErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var loadingSection: some View {
        Section {
            HStack(spacing: 10) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .id(loadingSessionID)
                Text("正在查询教室状态...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 18)
            .phaseAnimator([0.86, 1.0], trigger: loadingUsageData) { content, phase in
                content
                    .opacity(phase)
                    .scaleEffect(0.99 + (phase - 0.86) * 0.07)
            } animation: { _ in
                .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func resultSection(displaySnapshot: SelfStudyDisplaySnapshot) -> some View {
        if loadingUsageData && floors.isEmpty {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        } else if displaySnapshot.floors.isEmpty {
            Section {
                ContentUnavailableView(
                    "没有找到符合条件的教室",
                    systemImage: "magnifyingglass",
                    description: Text("可以尝试关闭筛选条件或切换教学楼。")
                )
            }
        } else {
            ForEach(displaySnapshot.floors) { floorDisplay in
                Section {
                    ForEach(floorDisplay.rooms) { roomDisplay in
                        NavigationLink {
                            SelfStudyRoomDetailView(
                                campusName: selectedCampus?.name ?? "",
                                buildingName: selectedBuilding?.name ?? "",
                                floorName: floorDisplay.floor.name,
                                room: roomDisplay.room,
                                sections: sections,
                                currentSectionIndex: activeSectionIndex,
                                closedSections: displaySnapshot.closedSections(for: roomDisplay.room)
                            )
                        } label: {
                            roomRow(roomDisplay)
                        }
                    }
                } header: {
                    floorHeader(floorDisplay)
                }
            }
        }
    }

    @ViewBuilder
    private func roomRow(_ roomDisplay: SelfStudyRoomDisplay) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(roomDisplay.room.name)
                    .font(.headline)

                if let studentCount = roomDisplay.room.actualStudentCount, studentCount > 0 {
                    compactMeta(systemImage: "person.2.fill", text: "在室约\(studentCount)人")
                        .foregroundStyle(.secondary)
                }

                if case .occupied(let course) = roomDisplay.availability, let course {
                    Text("本节课程：\(course.courseName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
            availabilityBadge(roomDisplay.availability)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func floorHeader(_ floorDisplay: SelfStudyFloorDisplay) -> some View {
        HStack {
            Text(floorDisplay.floor.name)
            Spacer()
            Text("空闲 \(floorDisplay.freeCount)/\(floorDisplay.floor.rooms.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(width: 112, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func availabilityBadge(_ availability: SelfStudyRoomAvailability) -> some View {
        let config: (title: String, color: Color, symbol: String) = {
            switch availability {
            case .free:
                return ("空闲", .green, "checkmark.circle.fill")
            case .selfStudy:
                return ("自习教室", .teal, "book.closed.fill")
            case .occupied:
                return ("占用", .orange, "clock.fill")
            case .closed:
                return ("关闭", .gray, "xmark.circle.fill")
            }
        }()

        HStack(spacing: 4) {
            Image(systemName: config.symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(config.title)
                .font(.caption2.weight(.semibold))
        }
        .frame(height: 16)
        .foregroundStyle(config.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(config.color.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private func compactMeta(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.caption)
        }
    }
    
    private func availabilityOrder(_ availability: SelfStudyRoomAvailability) -> Int {
        switch availability {
        case .free:
            return 0
        case .selfStudy:
            return 0
        case .occupied:
            return 1
        case .closed:
            return 2
        }
    }

    private func isFreeLike(_ availability: SelfStudyRoomAvailability) -> Bool {
        switch availability {
        case .free, .selfStudy:
            return true
        case .occupied, .closed:
            return false
        }
    }

    private func syncSelectedBuildingWithCampus() {
        guard let campus = selectedCampus else {
            selectedBuildingID = nil
            return
        }

        if let selectedBuildingID,
           campus.buildings.contains(where: { $0.id == selectedBuildingID }) {
            return
        }

        selectedBuildingID = campus.buildings.first?.id
    }

    @MainActor
    private func finishInitialLoading() async {
        guard loadingInitialData else {
            return
        }

        if let initialLoadingStartedAt {
            let elapsed = initialLoadingStartedAt.duration(to: .now)
            let remaining = minimumInitialLoadingDuration - elapsed
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            loadingInitialData = false
        }
    }

    @MainActor
    private func loadInitialData() async {
        let api = SelfStudyClassroomAPI()
        initialLoadingStartedAt = .now

        do {
            async let campusesTask = api.fetchCampuses()
            async let sectionsTask = api.fetchSections()

            let loadedCampuses = try await campusesTask
            let sectionPayload = try await sectionsTask

            campuses = loadedCampuses
            sections = sectionPayload.sections
            serverCurrentSectionIndex = sectionPayload.currentSection

            if selectedCampusID == nil {
                selectedCampusID = loadedCampuses.first?.id
            }
            syncSelectedBuildingWithCampus()

            await loadBuildingSnapshot()
        } catch {
            loadErrorMessage = errorText(error)
            await finishInitialLoading()
        }
    }

    @MainActor
    private func loadBuildingSnapshot() async {
        guard let selectedBuilding else {
            floors = []
            closedRooms = []
            await finishInitialLoading()
            return
        }

        let api = SelfStudyClassroomAPI()
        latestSnapshotRequestID += 1
        let requestID = latestSnapshotRequestID
        loadingUsageData = true
        loadingSessionID += 1

        do {
            let snapshot = try await api.fetchBuildingSnapshot(buildId: selectedBuilding.id)
            guard requestID == latestSnapshotRequestID else {
                return
            }
            floors = snapshot.floors
            closedRooms = snapshot.closedRooms
            loadErrorMessage = nil
        } catch {
            guard requestID == latestSnapshotRequestID else {
                return
            }
            loadErrorMessage = errorText(error)
            floors = []
            closedRooms = []
        }

        guard requestID == latestSnapshotRequestID else {
            return
        }
        loadingUsageData = false
        await finishInitialLoading()
    }

    private func errorText(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .sessionExpired:
                return "服务暂时不可用，请稍后重试。"
            case .noAccount:
                return "服务暂时不可用，请稍后重试。"
            case .remoteError(let message):
                return message
            case .runtimeError(let message):
                return message
            case .internalError:
                return "内部错误，请稍后重试。"
            }
        }

        return error.localizedDescription
    }
}

#Preview {
    NavigationStack {
        SelfStudyClassroomView()
    }
}
