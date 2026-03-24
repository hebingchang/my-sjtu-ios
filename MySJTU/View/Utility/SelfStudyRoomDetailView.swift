//
//  SelfStudyRoomDetailView.swift
//  MySJTU
//
//  Created by boar on 2026/03/24.
//

import SwiftUI

private enum SelfStudyRoomSectionStatus {
    case free
    case occupied(SelfStudyClassroomAPI.RoomCourse)
    case closed
}

private struct SelfStudyEnvironmentMetric: Identifiable {
    let key: String
    let title: String
    let symbol: String
    let tint: Color
    let valueText: String
    let displayOrder: Int

    var id: String {
        key
    }
}

struct SelfStudyRoomDetailView: View {
    let campusName: String
    let buildingName: String
    let floorName: String
    let room: SelfStudyClassroomAPI.Room
    let sections: [SelfStudyClassroomAPI.SectionTime]
    let currentSectionIndex: Int?
    let closedSections: Set<Int>

    @State private var hasLoadedRoomDetails = false
    @State private var loadingRoomDetails = false
    @State private var refreshingEnvironment = false
    @State private var roomDetailsErrorMessage: String?
    @State private var environmentErrorMessage: String?
    @State private var panoramaXMLURL: URL?
    @State private var panoramaPreviewImage: UIImage?
    @State private var loadingPanoramaPreview = false
    @State private var panoramaPreviewErrorMessage: String?
    @State private var roomAttributes: [SelfStudyClassroomAPI.RoomAttribute] = []
    @State private var roomEnvironmental: SelfStudyClassroomAPI.RoomEnvironmental?
    @State private var lastEnvironmentUpdatedAt: Date?

    private var effectiveCurrentSectionIndex: Int? {
        currentSectionIndex ?? sections.referenceSectionIndex()
    }

    private var currentSection: SelfStudyClassroomAPI.SectionTime? {
        guard let effectiveCurrentSectionIndex else {
            return nil
        }
        return sections.first { $0.sectionIndex == effectiveCurrentSectionIndex }
    }

    private var currentStatus: SelfStudyRoomSectionStatus {
        guard let effectiveCurrentSectionIndex else {
            return .free
        }
        return status(at: effectiveCurrentSectionIndex)
    }

    private var displayAttributes: [SelfStudyClassroomAPI.RoomAttribute] {
        roomAttributes.filter {
            $0.code.uppercased() != "ROOM_ATTR_360"
        }
    }

    private var environmentMetrics: [SelfStudyEnvironmentMetric] {
        guard let roomEnvironmental else {
            return []
        }

        return roomEnvironmental.sensorValues.map { key, value in
            let normalizedKey = key.lowercased()
            let config = environmentConfig(for: normalizedKey)
            return SelfStudyEnvironmentMetric(
                key: normalizedKey,
                title: config.title,
                symbol: config.symbol,
                tint: config.tint,
                valueText: formattedEnvironmentValue(rawValue: value, key: normalizedKey, unit: config.unit),
                displayOrder: config.order
            )
        }
        .sorted { lhs, rhs in
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder < rhs.displayOrder
            }
            return lhs.title < rhs.title
        }
    }

    private var isInitialRoomDetailsLoading: Bool {
        loadingRoomDetails && !hasLoadedRoomDetails
    }

    private var hasRoomDetailsError: Bool {
        roomDetailsErrorMessage?.isEmpty == false
    }

    private var hasEnvironmentError: Bool {
        environmentErrorMessage?.isEmpty == false
    }

    private var shouldShowEnvironmentSection: Bool {
        isInitialRoomDetailsLoading || !environmentMetrics.isEmpty || hasEnvironmentError
    }

    private var shouldShowFacilitySection: Bool {
        isInitialRoomDetailsLoading || panoramaXMLURL != nil || !displayAttributes.isEmpty || hasRoomDetailsError
    }

    private var shouldShowDetailNavigationSection: Bool {
        shouldShowEnvironmentSection || shouldShowFacilitySection
    }

    var body: some View {
        List {
            overviewSection
            detailNavigationSection
            sectionDetailSection
            todayCourseSection
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !hasLoadedRoomDetails else {
                return
            }
            await refreshRoomDetails(force: true)
        }
        .refreshable {
            await refreshRoomDetails(force: true)
        }
    }

    @ViewBuilder
    private var detailNavigationSection: some View {
        if shouldShowDetailNavigationSection {
            Section("详细信息") {
                NavigationLink {
                    List {
                        if shouldShowEnvironmentSection {
                            environmentSection
                        }
                        if shouldShowFacilitySection {
                            facilitySection
                        }
                    }
                    .navigationTitle("环境与设施")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    detailEntryRow(
                        title: "环境与设施",
                        subtitle: envFacilitySummaryText,
                        symbol: "square.grid.2x2.fill",
                        tint: .teal
                    )
                }
            }
        }
    }

    private var environmentSummaryText: String {
        guard let firstMetric = environmentMetrics.first else {
            return ""
        }

        return "\(firstMetric.title) \(firstMetric.valueText)"
    }

    private var envFacilitySummaryText: String {
        if isInitialRoomDetailsLoading {
            return "加载中..."
        }

        var parts: [String] = []

        if !environmentSummaryText.isEmpty {
            parts.append(environmentSummaryText)
        }
        if panoramaXMLURL != nil {
            parts.append("360° 全景")
        }
        if !displayAttributes.isEmpty {
            parts.append("设施\(displayAttributes.count)项")
        }

        if parts.isEmpty {
            return hasEnvironmentError || hasRoomDetailsError ? "加载失败" : "暂无详细信息"
        }

        if hasEnvironmentError || hasRoomDetailsError {
            parts.append("部分加载失败")
        }
        return parts.joined(separator: " · ")
    }

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(room.name)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 12) {
                    compactMeta(systemImage: "building.2", text: campusName)
                    compactMeta(systemImage: "mappin.and.ellipse", text: buildingName)
                    compactMeta(systemImage: "square.3.layers.3d", text: floorName)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let currentSection {
                    compactMeta(
                        systemImage: "clock",
                        text: "参考时段：第\(currentSection.sectionIndex)节 \(currentSection.startTime)-\(currentSection.endTime)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                statusBadge(for: currentStatus)

                if let studentCount = room.actualStudentCount, studentCount > 0 {
                    compactMeta(systemImage: "person.2.fill", text: "当前在室约 \(studentCount) 人")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var panoramaPreviewCard: some View {
        if loadingPanoramaPreview {
            ZStack {
                Rectangle()
                    .fill(Color.secondarySystemGroupedBackground.opacity(0.9))
                ProgressView()
                panoramaPreviewOverlay
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
        } else if let panoramaPreviewImage {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: panoramaPreviewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipped()
                panoramaPreviewOverlay
            }
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.secondarySystemGroupedBackground.opacity(0.9))
                Image(systemName: "view.3d")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
                panoramaPreviewOverlay
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
        }
    }

    private var panoramaPreviewOverlay: some View {
        VStack {
            Spacer()
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                HStack(spacing: 6) {
                    Image(systemName: "view.3d")
                    Text("点击查看 360° 全景")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(height: 56)
        }
    }

    @ViewBuilder
    private var facilitySection: some View {
        Section("教室设施") {
            if isInitialRoomDetailsLoading {
                loadingRow(text: "正在加载教室设施...")
            } else {
                if let panoramaXMLURL {
                    panoramaPreviewCard
                        .background(
                            NavigationLink("") {
                                PanoramaScreen(
                                    xmlURL: panoramaXMLURL,
                                    title: "\(room.name) 360°全景"
                                )
                            }
                                .opacity(0)
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if let panoramaPreviewErrorMessage, !panoramaPreviewErrorMessage.isEmpty {
                        Text("预览加载失败，可直接进入全景查看。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(displayAttributes) { attribute in
                    LabeledContent(attribute.name) {
                        Text(attribute.value)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.body)
                    .padding(.vertical, 2)
                }
            }

            if let roomDetailsErrorMessage, !roomDetailsErrorMessage.isEmpty {
                Text(roomDetailsErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var environmentSection: some View {
        Section {
            if isInitialRoomDetailsLoading {
                loadingRow(text: "正在加载环境数据...")
            }

            if let environmentErrorMessage, !environmentErrorMessage.isEmpty {
                Text(environmentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await refreshEnvironmentData()
                }
            } label: {
                HStack(spacing: 6) {
                    if refreshingEnvironment {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(refreshingEnvironment ? "刷新中..." : "刷新实时环境")
                }
                .font(.footnote)
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(refreshingEnvironment)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .environment(\.defaultMinListRowHeight, 1)
        } header: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("实时环境")
                    Spacer()
                    if let lastEnvironmentUpdatedAt {
                        Text("更新于 \(lastEnvironmentUpdatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let roomEnvironmental,
                   roomEnvironmental.hasSensor,
                   !environmentMetrics.isEmpty {
                    environmentMetricGrid
                        .padding(.horizontal, -16)
                }
            }
            .textCase(nil)
        }
    }

    @ViewBuilder
    private var sectionDetailSection: some View {
        Section("节次详情") {
            if sections.isEmpty {
                Text("暂无节次信息")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections) { section in
                    let sectionStatus = status(at: section.sectionIndex)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text("第\(section.sectionIndex)节")
                                .font(.subheadline.weight(.semibold))
                            Text("\(section.startTime)-\(section.endTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            statusBadge(for: sectionStatus)
                        }

                        switch sectionStatus {
                        case .occupied(let course):
                            Text("\(course.courseName)\(course.teacherName == nil ? "" : " · \(course.teacherName!)")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        case .closed:
                            Text("该节次教室关闭")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .free:
                            EmptyView()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var todayCourseSection: some View {
        Section("今日课程") {
            if room.courses.isEmpty {
                Text("暂无课程安排")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(room.courses.sorted(by: { lhs, rhs in
                    if lhs.startSection != rhs.startSection {
                        return lhs.startSection < rhs.startSection
                    }
                    return lhs.endSection < rhs.endSection
                })) { course in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.courseName)
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 10) {
                            compactMeta(systemImage: "clock", text: "第\(course.startSection)-\(course.endSection)节")
                            if let teacherName = course.teacherName, !teacherName.isEmpty {
                                compactMeta(systemImage: "person", text: teacherName)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var environmentMetricGrid: some View {
        let columns = [
            GridItem(.flexible(minimum: 0), spacing: 12),
            GridItem(.flexible(minimum: 0), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(environmentMetrics) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: metric.symbol)
                        Text(metric.title)
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(metric.valueText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(metric.tint)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.secondarySystemGroupedBackground.opacity(0.9))
                )
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func detailEntryRow(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func loadingRow(text: String) -> some View {
        HStack(spacing: 10) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func status(at sectionIndex: Int) -> SelfStudyRoomSectionStatus {
        if closedSections.contains(sectionIndex) {
            return .closed
        }

        if let course = room.courses.first(where: { $0.startSection <= sectionIndex && $0.endSection >= sectionIndex }) {
            return .occupied(course)
        }

        return .free
    }

    @ViewBuilder
    private func statusBadge(for status: SelfStudyRoomSectionStatus) -> some View {
        let config: (title: String, color: Color, symbol: String) = {
            switch status {
            case .free:
                if room.isSelfStudyRoom {
                    return ("自习教室", .teal, "book.closed.fill")
                }
                return ("空闲", .green, "checkmark.circle.fill")
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
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .foregroundStyle(config.color)
        .background(config.color.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private func compactMeta(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
        }
    }

    @MainActor
    private func refreshRoomDetails(force: Bool) async {
        guard force || !hasLoadedRoomDetails else {
            return
        }

        let api = SelfStudyClassroomAPI()

        loadingRoomDetails = true
        roomDetailsErrorMessage = nil
        environmentErrorMessage = nil

        async let panoramaTask = api.fetchRoomPanoramaXMLURL(roomId: room.id)
        async let attributesTask = api.fetchRoomAttributes(roomId: room.id)
        async let environmentTask = api.fetchRoomEnvironmental(roomId: room.id)

        var detailErrors: [String] = []

        do {
            panoramaXMLURL = try await panoramaTask
            if let panoramaXMLURL {
                await loadPanoramaPreviewImage(xmlURL: panoramaXMLURL)
            } else {
                panoramaPreviewImage = nil
                panoramaPreviewErrorMessage = nil
                loadingPanoramaPreview = false
            }
        } catch {
            panoramaXMLURL = nil
            panoramaPreviewImage = nil
            panoramaPreviewErrorMessage = nil
            loadingPanoramaPreview = false
            detailErrors.append("360 全景：\(errorText(error))")
        }

        do {
            roomAttributes = try await attributesTask
        } catch {
            roomAttributes = []
            detailErrors.append("教室属性：\(errorText(error))")
        }

        do {
            roomEnvironmental = try await environmentTask
            lastEnvironmentUpdatedAt = Date()
        } catch {
            roomEnvironmental = nil
            environmentErrorMessage = errorText(error)
        }

        roomDetailsErrorMessage = detailErrors.isEmpty ? nil : detailErrors.joined(separator: "\n")
        loadingRoomDetails = false
        hasLoadedRoomDetails = true
    }

    @MainActor
    private func loadPanoramaPreviewImage(xmlURL: URL) async {
        loadingPanoramaPreview = true
        panoramaPreviewErrorMessage = nil

        defer {
            if panoramaXMLURL == xmlURL {
                loadingPanoramaPreview = false
            }
        }

        do {
            let (xmlData, response) = try await URLSession.shared.data(from: xmlURL)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw APIError.runtimeError("全景配置拉取失败")
            }

            let config = try PanoramaXMLParser.parse(data: xmlData)
            let previewTilePaths = config.previewTilePaths()
            guard !previewTilePaths.isEmpty else {
                throw APIError.runtimeError("全景配置缺少预览图")
            }

            let baseURL = xmlURL.deletingLastPathComponent()
            var previewImage: UIImage?
            var lastImageError: Error?

            for previewTilePath in previewTilePaths {
                guard let imageURL = URL(string: previewTilePath, relativeTo: baseURL)?.absoluteURL else {
                    continue
                }

                do {
                    previewImage = try await RemoteImageLoader.shared.image(for: imageURL)
                    break
                } catch {
                    lastImageError = error
                }
            }

            guard let image = previewImage else {
                if let lastImageError {
                    throw lastImageError
                }
                throw APIError.runtimeError("预览图地址无效")
            }

            guard panoramaXMLURL == xmlURL else {
                return
            }

            panoramaPreviewImage = image
            panoramaPreviewErrorMessage = nil
        } catch {
            guard panoramaXMLURL == xmlURL else {
                return
            }

            panoramaPreviewImage = nil
            panoramaPreviewErrorMessage = errorText(error)
        }
    }

    @MainActor
    private func refreshEnvironmentData() async {
        let api = SelfStudyClassroomAPI()

        refreshingEnvironment = true
        defer { refreshingEnvironment = false }

        do {
            roomEnvironmental = try await api.fetchRoomEnvironmental(roomId: room.id)
            environmentErrorMessage = nil
            lastEnvironmentUpdatedAt = Date()
        } catch {
            environmentErrorMessage = errorText(error)
        }
    }

    private func environmentConfig(for key: String) -> (
        title: String,
        symbol: String,
        unit: String?,
        tint: Color,
        order: Int
    ) {
        switch key {
        case "temp":
            return ("温度", "thermometer.medium", "℃", .orange, 0)
        case "hum":
            return ("湿度", "drop.fill", "%", .blue, 1)
        case "pm":
            return ("PM2.5", "aqi.medium", "μg/m³", .green, 2)
        case "co":
            return ("CO₂", "wind", "ppm", .mint, 3)
        case "lux":
            return ("照度", "sun.max.fill", "lx", .yellow, 4)
        case "tvoc":
            return ("TVOC", "waveform.path.ecg", "mg/m³", .teal, 5)
        default:
            return (key.uppercased(), "dot.radiowaves.left.and.right", nil, .secondary, 100)
        }
    }

    private func formattedEnvironmentValue(rawValue: String, key: String, unit: String?) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(trimmed) else {
            return unit.map { "\(trimmed) \($0)" } ?? trimmed
        }

        let formatted: String = {
            switch key {
            case "temp", "hum":
                return number.formatted(.number.precision(.fractionLength(0...1)))
            case "tvoc":
                return number.formatted(.number.precision(.fractionLength(0...3)))
            default:
                return number.formatted(.number.precision(.fractionLength(0...2)))
            }
        }()

        return unit.map { "\(formatted) \($0)" } ?? formatted
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
    let room = SelfStudyClassroomAPI.Room(
        id: 1,
        name: "下院401",
        roomCode: "WX402",
        indexNum: 1,
        isSelfStudyRoom: true,
        courses: [
            .init(courseName: "示例课程", teacherName: "张老师", startSection: 3, endSection: 4)
        ],
        actualStudentCount: 0
    )

    let sections: [SelfStudyClassroomAPI.SectionTime] = [
        .init(endTime: "08:45", startTime: "08:00", sectionIndex: 1),
        .init(endTime: "09:40", startTime: "08:55", sectionIndex: 2),
        .init(endTime: "10:45", startTime: "10:00", sectionIndex: 3)
    ]

    return NavigationStack {
        SelfStudyRoomDetailView(
            campusName: "闵行校区",
            buildingName: "下院",
            floorName: "四层",
            room: room,
            sections: sections,
            currentSectionIndex: 2,
            closedSections: []
        )
    }
}
