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

private struct SelfStudyFloorDisplay: Identifiable {
    let floor: SelfStudyClassroomAPI.Floor
    let rooms: [SelfStudyClassroomAPI.Room]

    var id: Int {
        floor.id
    }
}

struct SelfStudyClassroomView: View {
    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []

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
    @State private var loadingSessionID: Int = 0

    private var account: WebAuthAccount? {
        accounts.first { $0.provider == .jaccount }
    }

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
        if let serverCurrentSectionIndex {
            return serverCurrentSectionIndex
        }

        let now = Date.now
        for section in sections {
            guard let start = now.timeOfDay("HH:mm", timeStr: section.startTime),
                  let end = now.timeOfDay("HH:mm", timeStr: section.endTime) else {
                continue
            }

            if now >= start && now <= end {
                return section.sectionIndex
            }
        }

        for section in sections {
            if let start = now.timeOfDay("HH:mm", timeStr: section.startTime), now < start {
                return section.sectionIndex
            }
        }

        return sections.last?.sectionIndex
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

    private var closedSectionsByCode: [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        for room in closedRooms {
            result[room.roomCode.uppercased()] = room.closedSections
        }
        return result
    }

    private var closedSectionsByName: [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        for room in closedRooms {
            result[room.roomName] = room.closedSections
        }
        return result
    }
    
    private var displayedFloors: [SelfStudyFloorDisplay] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return floors
            .map { floor in
                let rooms = floor.rooms
                    .filter { room in
                        if !keyword.isEmpty {
                            let searchableText = room.name.lowercased()
                            if !searchableText.contains(keyword) {
                                return false
                            }
                        }

                        if onlyShowFreeRooms {
                            return isFreeLike(availability(for: room, at: activeSectionIndex))
                        }

                        return true
                    }
                    .sorted { lhs, rhs in
                        let leftOrder = availabilityOrder(availability(for: lhs, at: activeSectionIndex))
                        let rightOrder = availabilityOrder(availability(for: rhs, at: activeSectionIndex))

                        if leftOrder != rightOrder {
                            return leftOrder < rightOrder
                        }

                        if lhs.indexNum != rhs.indexNum {
                            return (lhs.indexNum ?? .max) < (rhs.indexNum ?? .max)
                        }

                        return lhs.name < rhs.name
                    }

                return SelfStudyFloorDisplay(floor: floor, rooms: rooms)
            }
            .filter { !$0.rooms.isEmpty }
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
            } else if account == nil {
                ContentUnavailableView(
                    "未找到可用账号",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("请先在设置中登录 jAccount 账号后再使用自习教室。")
                )
                .transition(.opacity)
            } else {
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
                        resultSection
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
                    await loadBuildingSnapshot(showLoader: true)
                }
                .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: loadingUsageData)
                .animation(.snappy(duration: 0.3, extraBounce: 0.02), value: displayedFloors.count)
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

            floors = []
            closedRooms = []
            loadingUsageData = true
            loadingSessionID += 1

            Task {
                await loadBuildingSnapshot(showLoader: false)
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
                LabeledContent("当前参考节次") {
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
    private var resultSection: some View {
        if loadingUsageData && floors.isEmpty {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        } else if displayedFloors.isEmpty {
            Section {
                ContentUnavailableView(
                    "没有找到符合条件的教室",
                    systemImage: "magnifyingglass",
                    description: Text("可以尝试关闭筛选条件或切换教学楼。")
                )
            }
        } else {
            ForEach(displayedFloors) { floorDisplay in
                Section {
                    ForEach(floorDisplay.rooms) { room in
                        NavigationLink {
                            SelfStudyRoomDetailView(
                                campusName: selectedCampus?.name ?? "",
                                buildingName: selectedBuilding?.name ?? "",
                                floorName: floorDisplay.floor.name,
                                room: room,
                                sections: sections,
                                currentSectionIndex: activeSectionIndex,
                                closedSections: closedSections(for: room),
                                authCookies: account?.cookies.compactMap(\.httpCookie) ?? []
                            )
                        } label: {
                            roomRow(room)
                        }
                    }
                } header: {
                    floorHeader(floorDisplay.floor)
                }
                .sectionIndexLabel(floorIndexLabel(for: floorDisplay.floor))
            }
        }
    }

    @ViewBuilder
    private func roomRow(_ room: SelfStudyClassroomAPI.Room) -> some View {
        let availability = availability(for: room, at: activeSectionIndex)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(room.name)
                    .font(.headline)

                if let studentCount = room.actualStudentCount, studentCount > 0 {
                    compactMeta(systemImage: "person.2.fill", text: "在室约\(studentCount)人")
                        .foregroundStyle(.secondary)
                }

                if case .occupied(let course) = availability, let course {
                    Text("本节课程：\(course.courseName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
            availabilityBadge(availability)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func floorHeader(_ floor: SelfStudyClassroomAPI.Floor) -> some View {
        let freeCount = floor.rooms.reduce(into: 0) { result, room in
            if isFreeLike(availability(for: room, at: activeSectionIndex)) {
                result += 1
            }
        }

        HStack {
            Text(floor.name)
            Spacer()
            Text("空闲 \(freeCount)/\(floor.rooms.count)")
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
    
    private func floorIndexLabel(for floor: SelfStudyClassroomAPI.Floor) -> String? {
        if let floorIndex = floor.indexNum {
            if floorIndex < 0 {
                return "B\(-floorIndex)F"
            }
            return "\(floorIndex)F"
        }

        let trimmedFloorName = floor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFloorName.isEmpty else {
            return nil
        }
        
        if let match = trimmedFloorName.range(of: #"-?\d+"#, options: .regularExpression),
           let number = Int(trimmedFloorName[match]) {
            if number < 0 {
                return "B\(-number)F"
            }
            return "\(number)F"
        }

        return String(trimmedFloorName.prefix(1))
    }

    private func isAllDayClosed(_ room: SelfStudyClassroomAPI.Room) -> Bool {
        let roomClosedSections = closedSections(for: room)
        let sectionIndexes = Set(sections.map(\.sectionIndex))

        guard !sectionIndexes.isEmpty else {
            return false
        }

        return sectionIndexes.isSubset(of: roomClosedSections)
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

    private func closedSections(for room: SelfStudyClassroomAPI.Room) -> Set<Int> {
        if let sections = closedSectionsByCode[room.roomCode.uppercased()] {
            return sections
        }

        if let sections = closedSectionsByName[room.name] {
            return sections
        }

        return []
    }

    private func availability(for room: SelfStudyClassroomAPI.Room, at sectionIndex: Int?) -> SelfStudyRoomAvailability {
        let closedSections = closedSections(for: room)

        guard let sectionIndex else {
            if !closedSections.isEmpty && closedSections.count >= sections.count {
                return .closed
            }
            return room.isSelfStudyRoom ? .selfStudy : .free
        }

        if closedSections.contains(sectionIndex) {
            return .closed
        }

        let course = room.courses.first {
            $0.startSection <= sectionIndex && $0.endSection >= sectionIndex
        }
        if course != nil {
            return .occupied(course)
        }

        return room.isSelfStudyRoom ? .selfStudy : .free
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
    private func finishInitialLoading() {
        guard loadingInitialData else {
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            loadingInitialData = false
        }
    }

    @MainActor
    private func loadInitialData() async {
        guard let account else {
            finishInitialLoading()
            loadErrorMessage = "未找到可用账号。"
            return
        }

        let cookies = account.cookies.compactMap(\.httpCookie)
        let api = SelfStudyClassroomAPI(cookies: cookies)

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
            finishInitialLoading()
        }
    }

    @MainActor
    private func loadBuildingSnapshot(showLoader: Bool = true) async {
        guard let account else {
            finishInitialLoading()
            loadErrorMessage = "未找到可用账号。"
            return
        }

        guard let selectedBuilding else {
            finishInitialLoading()
            floors = []
            closedRooms = []
            return
        }

        let cookies = account.cookies.compactMap(\.httpCookie)
        let api = SelfStudyClassroomAPI(cookies: cookies)

        if showLoader {
            loadingUsageData = true
            loadingSessionID += 1
        }

        do {
            let snapshot = try await api.fetchBuildingSnapshot(buildId: selectedBuilding.id)
            floors = snapshot.floors
            closedRooms = snapshot.closedRooms
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = errorText(error)
            floors = []
            closedRooms = []
        }

        loadingUsageData = false
        finishInitialLoading()
    }

    private func errorText(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .sessionExpired:
                return "登录状态已过期，请重新登录后再试。"
            case .noAccount:
                return "未找到可用账号，请先登录 jAccount。"
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
