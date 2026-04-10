//
//  ScheduleView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI
import GRDBQuery
import WidgetKit
import UIKit

let weekModeLeading: CGFloat = 48

private enum ScheduleGridMetrics {
    static let weekSlotHeightPhone: CGFloat = 64
    static let weekSlotHeightPad: CGFloat = 72
    static let dayHourSpacingPhone: CGFloat = 20
    static let dayHourSpacingPad: CGFloat = 26
    static let dayHourHeightPhone: CGFloat = 20
    static let dayHourHeightPad: CGFloat = 26

    static func weekSlotHeight(isPad: Bool) -> CGFloat {
        isPad ? weekSlotHeightPad : weekSlotHeightPhone
    }

    static func dayHourSpacing(isPad: Bool) -> CGFloat {
        isPad ? dayHourSpacingPad : dayHourSpacingPhone
    }

    static func dayHourHeight(isPad: Bool) -> CGFloat {
        isPad ? dayHourHeightPad : dayHourHeightPhone
    }
}

private func scheduleGridDividerColor(hasCustomBackgroundImage: Bool) -> Color {
    Color(hasCustomBackgroundImage ? UIColor.systemGray4 : UIColor.systemGray5)
}

struct WeekView: View {
    @Binding var selectedDay: Date
    let week: Date
    let displayMode: DisplayMode

    private var weekDays: [Date] {
        Array(week.weekDays())
    }

    private var todayAccentColor: Color {
        Color("AccentColor")
    }

    private func foregroundStyle(isCurrentDay: Bool, isToday: Bool) -> Color {
        if displayMode == .day && isCurrentDay {
            return Color(UIColor.systemBackground)
        }
        if isToday {
            return todayAccentColor
        }
        return Color(UIColor.label)
    }

    private func backgroundStyle(isCurrentDay: Bool, isToday: Bool) -> Color {
        if displayMode == .week {
            return Color(UIColor.clear)
        }
        if isCurrentDay {
            return isToday ? todayAccentColor : Color(UIColor.label)
        }
        return Color(UIColor.clear)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { date in
                let isCurrentDay = date.isSameDay(as: selectedDay)
                let isToday = date.isSameDay(as: Date())

                Text(String(date.get(.day).day!))
                .frame(maxWidth: .infinity)
                .font(.title3)
                .fontWeight((displayMode == .day && isCurrentDay) ? .medium : .regular)
                .foregroundStyle(foregroundStyle(isCurrentDay: isCurrentDay, isToday: isToday))
                .padding(8)
                .background(backgroundStyle(isCurrentDay: isCurrentDay, isToday: isToday))
                .clipShape(Circle())
                .animation(.easeInOut(duration: 0.2), value: selectedDay)
                .onTapGesture {
                    selectedDay = date
                }
                .disabled(displayMode == .week)
            }
        }
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case day, week
    var id: Self {
        self
    }
}

enum ImportError: Error {
    case invalidSemester
    case internalError
    case invalidAccount
    case sessionExpired
    case todo
}

struct ScheduleViewTitle: View {
    private let toolbarButtonSize: CGFloat = 48
    private let titleRowMinHeight: CGFloat = 52

    @Binding var displayMode: DisplayMode
    @EnvironmentObject var progressor: Progressor
    @EnvironmentObject private var appConfig: AppConfig
    @Environment(\.colorScheme) private var colorScheme

    var selectedDay: Date
    var college: College
    var showBothCollege: Bool
    @Binding var activeCustomSchedule: CustomSchedule?

    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var showAlert = false
    @State private var showCustomScheduleSheet = false
    @State private var presentAccountPage = false
    @State private var alertError: ImportError?

    private var jAccount: WebAuthAccount? {
        accounts.first { $0.provider == .jaccount }
    }

    private var shsmuAccount: WebAuthAccount? {
        accounts.first { $0.provider == .shsmu }
    }

    private var displayModeIcon: String {
        displayMode == .day ? "calendar.day.timeline.left" : "calendar"
    }

    private var customScheduleNavigationTitle: String {
        activeCustomSchedule?.name ?? "添加自定义日程"
    }

    private var importAlertTitle: String {
        alertError == .todo ? "暂时无法添加日程" : "暂时无法导入日程"
    }

    @ViewBuilder
    private func importAlertActions(for detail: ImportError) -> some View {
        if detail == .sessionExpired || detail == .invalidAccount {
            Button("前往设置") {
                presentAccountPage = true
            }
            Button("以后", role: .cancel) {
                showAlert = false
            }
        }
    }

    @ViewBuilder
    private func importAlertMessage(for detail: ImportError) -> some View {
        switch detail {
        case .internalError:
            Text("内部错误")
        case .invalidAccount:
            Text("没有有效的\(college.provider!.descriptionShort)账号")
        case .invalidSemester:
            Text("当前日不属于任何有效学期")
        case .sessionExpired:
            Text("\(college.provider!.description)会话已过期，请重新登录")
        case .todo:
            Text("该功能尚未实现，敬请期待！")
        }
    }

    @ViewBuilder
    private func menuButtonIcon(_ systemName: String, highlighted: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, design: .rounded))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(highlighted ? Color("AccentColor") : Color(UIColor.label))
            .frame(width: toolbarButtonSize, height: toolbarButtonSize)
    }

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 16) {
            Text(selectedDay.localeMonth())
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            GlassEffectContainer {
                HStack {
                    Menu {
                        Picker(selection: $displayMode, label: Text("")) {
                            Label("单日", systemImage: "calendar.day.timeline.left").tag(DisplayMode.day)
                            Label("一周", systemImage: "calendar").tag(DisplayMode.week)
                        }
                    } label: {
                        menuButtonIcon(displayModeIcon)
                            .glassEffect(.regular.interactive())
                            .glassEffectUnion(id: "schedule-toolbar-menu", namespace: namespace)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        importMenuContent
                    } label: {
                        menuButtonIcon("plus")
                            .glassEffect(.regular.interactive())
                            .glassEffectUnion(id: "schedule-toolbar-menu", namespace: namespace)
                    }
                    .buttonStyle(.plain)
                    .onChange(of: activeCustomSchedule) {
                        if activeCustomSchedule != nil {
                            showCustomScheduleSheet = true
                        }
                    }
                    .sheet(isPresented: $showCustomScheduleSheet, onDismiss: {
                        activeCustomSchedule = nil
                    }) {
                        NavigationStack {
                            CustomScheduleEditorView(customSchedule: activeCustomSchedule)
                                .navigationTitle(customScheduleNavigationTitle)
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    .sheet(isPresented: $presentAccountPage) {
                        NavigationStack {
                            AccountView(provider: college.provider!)
                                .navigationTitle("\(college.provider!.descriptionShort)账户")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    .alert(importAlertTitle, isPresented: $showAlert, presenting: alertError) { detail in
                        importAlertActions(for: detail)
                    } message: { detail in
                        importAlertMessage(for: detail)
                    }
                }
                .frame(height: toolbarButtonSize)
            }
        }
        .frame(minHeight: titleRowMinHeight, alignment: .center)
    }

    @ViewBuilder
    private var importMenuContent: some View {
        if appConfig.appStatus == .review {
            Button("导入日程", systemImage: "square.and.arrow.down") {
                importReviewSchedule()
            }
        } else {
            if college == .sjtu {
                Button("从教学信息服务网导入", systemImage: "square.and.arrow.down") {
                    importSJTUSchedule()
                }
            }

            if college == .sjtug || (college == .sjtu && showBothCollege) {
                Button("从研究生选课系统导入", systemImage: "square.and.arrow.down") {
                    importSJTUGSchedule()
                }
            }

            if college == .shsmu {
                Button("从医学院教务系统导入", systemImage: "square.and.arrow.down") {
                    importSHSMUSchedule()
                }
            }

            if college == .joint {
                Button("从密院选课系统导入", systemImage: "square.and.arrow.down") {
                    importJointSchedule()
                }
            }
        }

        Button("添加自定义日程", systemImage: "plus") {
            showCustomScheduleSheet = true
        }
    }

    private func showImportAlert(_ error: ImportError) {
        alertError = error
        showAlert.toggle()
    }

    private func importReviewSchedule() {
        do {
            let semester = try Eloquent.getSemester(college: college, date: selectedDay)

            Task {
                if let semester {
                    let api = SJTUOpenAPI(tokens: [])
                    let schedules = try await api.getSchedules(
                        semester: semester,
                        sample: true
                    )
                    progressor.progress = Progress(description: "正在导入日程", value: 0.6)
                    try await Eloquent.insertSchedules(semester: semester, college: college, schedules: schedules, deleteExisting: true)
                    WidgetCenter.shared.reloadAllTimelines()
                    progressor.progress = Progress(description: "导入日程完成", value: 1)
                } else {
                    showImportAlert(.invalidSemester)
                }
            }
        } catch {
            print(error)
        }
    }

    private func importSJTUSchedule() {
        guard let account = jAccount else {
            showImportAlert(.invalidAccount)
            return
        }

        do {
            let semester = try Eloquent.getSemester(college: .sjtu, date: selectedDay)
            if let semester {
                Task {
                    do {
                        progressor.progress = Progress(description: "正在初始化", value: 0)
                        let api = SJTUOpenAPI(tokens: account.tokens)
                        progressor.progress = Progress(description: "正在同步日程", value: 0.1)
                        let schedules = try await api.getSchedules(semester: semester)
                        progressor.progress = Progress(description: "正在导入日程", value: 0.6)
                        try await Eloquent.insertSchedules(semester: semester, college: .sjtu, schedules: schedules, deleteExisting: true)
                        WidgetCenter.shared.reloadAllTimelines()
                        progressor.progress = Progress(description: "导入日程完成", value: 1)
                    } catch {
                        progressor.progress = Progress(description: "导入日程失败", value: -1)
                    }
                }
            } else {
                showImportAlert(.invalidSemester)
            }
        } catch {
            showImportAlert(.internalError)
        }
    }

    private func importSJTUGSchedule() {
        guard let account = jAccount else {
            showImportAlert(.invalidAccount)
            return
        }

        do {
            let semester = try Eloquent.getSemester(college: .sjtug, date: selectedDay)
            if let semester {
                Task {
                    do {
                        progressor.progress = Progress(description: "正在初始化", value: 0)
                        let api = SJTUGOpenAPI(cookies: account.cookies.map { cookie in
                            cookie.httpCookie!
                        })
                        progressor.progress = Progress(description: "正在同步日程", value: 0.1)
                        let schedules = try await api.getSchedules(semester: semester)
                        progressor.progress = Progress(description: "正在导入日程", value: 0.6)
                        try await Eloquent.insertSchedules(semester: semester, college: .sjtug, schedules: schedules, deleteExisting: true)
                        WidgetCenter.shared.reloadAllTimelines()
                        progressor.progress = Progress(description: "导入日程完成", value: 1)
                    } catch {
                        print(error)
                        progressor.progress = Progress(description: "导入日程失败", value: -1)
                    }
                }
            } else {
                showImportAlert(.invalidSemester)
            }
        } catch {
            showImportAlert(.internalError)
        }
    }

    private func importSHSMUSchedule() {
        guard let account = shsmuAccount else {
            showImportAlert(.invalidAccount)
            return
        }

        do {
            let semester = try Eloquent.getSemester(college: college, date: selectedDay)
            if let semester {
                Task {
                    do {
                        progressor.progress = Progress(description: "正在初始化", value: 0)
                        let api = SHSMUOpenAPI(cookies: account.cookies.map { cookie in
                            cookie.httpCookie!
                        })
                        progressor.progress = Progress(description: "正在检查会话", value: 0.1)
                        let status = try await account.checkSession()
                        if status == .expired {
                            progressor.progress = Progress(description: "会话已过期", value: -1)
                            try await Task.sleep(for: .seconds(2))
                            showImportAlert(.sessionExpired)
                            return
                        }

                        progressor.progress = Progress(description: "正在同步日程", value: 0.2)
                        let schedules = try await api.getSchedules(semester: semester) { progress in
                            DispatchQueue.main.async {
                                progressor.progress = Progress(description: "正在获取日程信息 \(Int(progress * 100))%", value: 0.4 + (0.8 - 0.4) * Float(progress))
                            }
                        }

                        progressor.progress = Progress(description: "正在导入日程", value: 0.8)
                        try await Eloquent.insertSchedules(semester: semester, college: college, schedules: schedules, deleteExisting: true)
                        WidgetCenter.shared.reloadAllTimelines()
                        progressor.progress = Progress(description: "导入日程完成", value: 1)
                    } catch {
                        print(error)
                        progressor.progress = Progress(description: "导入日程失败", value: -1)
                    }
                }
            } else {
                showImportAlert(.invalidSemester)
            }
        } catch {
            showImportAlert(.internalError)
        }
    }

    private func importJointSchedule() {
        guard let account = jAccount else {
            showImportAlert(.invalidAccount)
            return
        }

        do {
            guard let jointSemester = try Eloquent.getSemester(college: college, date: selectedDay) else {
                showImportAlert(.invalidSemester)
                return
            }

            let sjtuSemester = try Eloquent.getSemester(college: .sjtu, date: selectedDay)
            Task {
                do {
                    progressor.progress = Progress(description: "正在初始化", value: 0)
                    let api = JointOpenAPI(cookies: account.cookies.compactMap { cookie in
                        cookie.httpCookie
                    }, tokens: account.tokens)
                    progressor.progress = Progress(description: "正在获取用户信息", value: 0.1)
                    let userInfo = try await api.getUserInfo()
                    progressor.progress = Progress(description: "正在匹配当前学期", value: 0.3)
                    let termId = try await api.getCurrentTermId(for: selectedDay)
                    progressor.progress = Progress(description: "正在同步日程", value: 0.6)
                    let schedules = try await api.getSchedules(
                        jointSemester: jointSemester,
                        sjtuSemester: sjtuSemester,
                        termId: termId,
                        studentId: userInfo.session.userId
                    )
                    progressor.progress = Progress(description: "正在导入日程", value: 0.8)
                    try await Eloquent.insertSchedules(semester: jointSemester, college: college, schedules: schedules, deleteExisting: true)
                    WidgetCenter.shared.reloadAllTimelines()
                    progressor.progress = Progress(description: "导入日程完成", value: 1)
                } catch APIError.runtimeError {
                    progressor.progress = Progress(description: "当前日期不属于任何有效学期", value: -1)
                    try? await Task.sleep(for: .seconds(2))
                    showImportAlert(.invalidSemester)
                } catch {
                    print(error)
                    progressor.progress = Progress(description: "导入日程失败", value: -1)
                }
            }
        } catch {
            showImportAlert(.internalError)
        }
    }
}

struct WeekTabView: View {
    // Keep the prefetched page window tight to reduce render work during mode switches.
    private static let initialWindowRadius = 3
    @Binding var selectedDay: Date
    let baseDay: Date
    let displayMode: DisplayMode
    @State private var scrollPosition: ScrollPosition
    @State private var data = Array(-Self.initialWindowRadius...Self.initialWindowRadius)

    private let windowRadius = Self.initialWindowRadius

    init(selectedDay: Binding<Date>, baseDay: Date, displayMode: DisplayMode) {
        self._selectedDay = selectedDay
        self.baseDay = baseDay
        self.displayMode = displayMode
        self.scrollPosition = .init(id: selectedDay.wrappedValue.weeksSince(baseDay))
    }

    private func recenterData(around position: Int) {
        data = Array(position - windowRadius...position + windowRadius)
    }

    private func syncScrollToSelectedDay() {
        let id = selectedDay.weeksSince(baseDay)
        let position = scrollPosition.viewID(type: Int.self)!
        guard id != position else { return }

        if data.contains(id) {
            withAnimation {
                scrollPosition.scrollTo(id: id)
            }
            return
        }

        recenterData(around: id)
        scrollPosition.scrollTo(id: id)
    }

    private func syncSelectedDayToScrollPosition() {
        let position = scrollPosition.viewID(type: Int.self)!
        let weekDelta = position - selectedDay.weeksSince(baseDay)

        if weekDelta != 0 {
            selectedDay = selectedDay.addWeeks(weekDelta)
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(data, id: \.self) { offset in
                    let week = baseDay.addWeeks(offset)
                    WeekView(selectedDay: $selectedDay, week: week, displayMode: displayMode)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onChange(of: selectedDay) {
            syncScrollToSelectedDay()
        }
        .onChange(of: scrollPosition) {
            syncSelectedDayToScrollPosition()
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            let position = scrollPosition.viewID(type: Int.self)!

            if newPhase == .idle {
                recenterData(around: position)
            }
        }
        .frame(height: 40)
    }
}

struct ScheduleVerticalScrollMetrics: Equatable {
    let contentOffsetY: CGFloat
    let maxContentOffsetY: CGFloat
    let topContentOffsetY: CGFloat

    static let zero = Self(contentOffsetY: 0, maxContentOffsetY: 0, topContentOffsetY: 0)

    init(contentOffsetY: CGFloat, maxContentOffsetY: CGFloat, topContentOffsetY: CGFloat) {
        self.contentOffsetY = contentOffsetY
        self.maxContentOffsetY = max(maxContentOffsetY, 0)
        self.topContentOffsetY = topContentOffsetY
    }

    init(geometry: ScrollGeometry) {
        self.init(
            contentOffsetY: geometry.contentOffset.y,
            maxContentOffsetY: geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom - geometry.containerSize.height,
            topContentOffsetY: -geometry.contentInsets.top
        )
    }
}

struct DayView: View {
    let day: Date
    let colleges: [College]
    let onScheduleTouch: (ScheduleInfo) -> Void
    let onCustomScheduleTouch: (CustomSchedule) -> Void

    @Query<SchedulesRequest> private var schedules: [ScheduleInfo]
    @Query<CustomSchedulesRequest> private var customSchedules: [CustomSchedule]
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @AppStorage("schedule.backgroundImage") private var backgroundImage: URL?
    @AppStorage("schedule.backgroundImage.landscape") private var landscapeBackgroundImage: URL?
    @State private var nowPosition: CGFloat?
    @State private var expandedOverlapGroupID: String?
    // Minute-level refresh is enough for the current-time indicator.
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(day: Date, colleges: [College], onScheduleTouch: @escaping (ScheduleInfo) -> Void, onCustomScheduleTouch: @escaping (CustomSchedule) -> Void) {
        self.day = day
        self.colleges = colleges
        self.onScheduleTouch = onScheduleTouch
        self.onCustomScheduleTouch = onCustomScheduleTouch
        _schedules = Query(constant: SchedulesRequest(colleges: colleges, date: day))
        _customSchedules = Query(constant: CustomSchedulesRequest(colleges: colleges, date: day))
    }

    private enum Layout {
        static let hourSpacing: CGFloat = 20
        static let hourHeight: CGFloat = 20
        static let hourFontSize: CGFloat = 14
        static let viewHorizontalPadding: CGFloat = 14
        static let axisVerticalPadding: CGFloat = 16
        static let dividerThickness: CGFloat = 1.2
        static let verticalDividerOffset: CGFloat = 12.6
        static let eventCardCornerRadius: CGFloat = 16
        static let eventCardHorizontalPadding: CGFloat = 12
        static let eventCardVerticalPadding: CGFloat = 10
        static let eventCardCompactVerticalPadding: CGFloat = 8
        static let eventCardCompactThreshold: CGFloat = 60
        static let overlapStackSpacingRatio: CGFloat = 0.022
        static let overlapDimmedOpacity: Double = 0.9
        static let overlapAnimation: Animation = .spring(response: 0.34, dampingFraction: 0.84, blendDuration: 0.12)
    }

    private struct TimedEventDescriptor {
        let id: String
        let start: CGFloat
        let end: CGFloat
    }

    private struct DayEventOverlapLayout {
        let groupID: String?
        let orderIndex: Int
        let groupSize: Int
        let expandedCenter: CGFloat

        var isOverlapping: Bool {
            groupID != nil
        }
    }

    private struct EventCardPlacement {
        let yPosition: CGFloat
        let isSeparated: Bool
        let isDimmed: Bool
    }

    private var hasCustomBackgroundImage: Bool {
        backgroundImage != nil || landscapeBackgroundImage != nil
    }

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var hourSpacing: CGFloat {
        ScheduleGridMetrics.dayHourSpacing(isPad: isPadDevice)
    }

    private var hourHeight: CGFloat {
        ScheduleGridMetrics.dayHourHeight(isPad: isPadDevice)
    }

    private var hourGridDividerColor: Color {
        scheduleGridDividerColor(hasCustomBackgroundImage: hasCustomBackgroundImage)
    }

    private var overlapLayoutsByEventID: [String: DayEventOverlapLayout] {
        let timedEvents = schedules.map(scheduleDescriptor) + customSchedules.map(customScheduleDescriptor)
        return computeOverlapLayouts(for: timedEvents)
    }

    private struct HourAxisView: View {
        let start: Int
        let finish: Int
        let hourSpacing: CGFloat
        let hourHeight: CGFloat

        var body: some View {
            VStack(alignment: .trailing, spacing: hourSpacing) {
                ForEach(start...finish, id: \.self) { hour in
                    Text("\(hour):00")
                        .frame(height: hourHeight)
                        .font(.system(size: DayView.Layout.hourFontSize, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
        }
    }

    private struct HourGridView: View {
        let start: Int
        let finish: Int
        let containerHeight: CGFloat
        let dividerColor: Color
        let hourSpacing: CGFloat
        let hourHeight: CGFloat

        var body: some View {
            ZStack {
                VStack(alignment: .trailing, spacing: hourSpacing) {
                    ForEach(start...finish, id: \.self) { _ in
                        VStack {
                            Rectangle()
                                .fill(dividerColor)
                                .frame(height: DayView.Layout.dividerThickness)
                        }
                        .frame(height: hourHeight)
                    }
                }

                Rectangle()
                    .fill(dividerColor)
                    .frame(width: DayView.Layout.dividerThickness, height: containerHeight)
                    .position(
                        x: DayView.Layout.verticalDividerOffset,
                        y: (hourHeight + DayView.Layout.dividerThickness + containerHeight) / 2
                    )
            }
        }
    }

    private struct EventCardSurfaceView<Content: View>: View {
        let colorHex: String
        let colorScheme: ColorScheme
        let overlapLayout: DayEventOverlapLayout?
        var isSeparated: Bool = false
        var isFocused: Bool = false
        var isDimmed: Bool = false
        @ViewBuilder let content: () -> Content
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        private var isRegularWidth: Bool { horizontalSizeClass == .regular }

        private var backgroundColor: Color {
            colorScheme == .light
            ? Color(UIColor.systemBackground)
            : Color(UIColor.secondarySystemBackground)
        }

        private var accentColor: Color {
            Color(hex: colorHex, opacity: colorScheme == .light ? 0.92 : 0.82)
        }

        private var cornerRadius: CGFloat { isRegularWidth ? 20 : DayView.Layout.eventCardCornerRadius }

        var body: some View {
            let cardShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let accentOpacityBoost = isFocused ? 1.12 : 1
            let primaryShadowColor = Color(
                hex: colorHex,
                opacity: colorScheme == .light
                ? (isFocused ? 0.18 : 0.1)
                : (isFocused ? 0.24 : 0.16)
            )
            let ambientShadowColor = Color(
                hex: colorHex,
                opacity: colorScheme == .light
                ? (isFocused ? 0.06 : 0)
                : (isFocused ? 0.08 : 0)
            )

            cardShape
                .fill(backgroundColor)
                .overlay {
                    cardShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: colorHex, opacity: (colorScheme == .light ? 0.28 : 0.42) * accentOpacityBoost),
                                    Color(hex: colorHex, opacity: (colorScheme == .light ? 0.16 : 0.3) * accentOpacityBoost),
                                    Color(hex: colorHex, opacity: (colorScheme == .light ? 0.08 : 0.18) * accentOpacityBoost)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    cardShape
                        .stroke(
                            Color(hex: colorHex, opacity: colorScheme == .light ? (isFocused ? 0.34 : 0.26) : (isFocused ? 0.46 : 0.38)),
                            lineWidth: isFocused ? 1.2 : 1
                        )
                }
                .clipShape(cardShape)
                .shadow(
                    color: primaryShadowColor,
                    radius: colorScheme == .light ? (isFocused ? 14 : 7) : (isFocused ? 10 : 6),
                    x: 0,
                    y: colorScheme == .light ? (isFocused ? 8 : 3) : (isFocused ? 6 : 2)
                )
                .shadow(
                    color: ambientShadowColor,
                    radius: isSeparated ? 7 : 0,
                    x: 0,
                    y: isSeparated ? 1 : 0
                )
                .overlay(alignment: .topLeading) {
                    content()
                }
                .overlay(alignment: .topTrailing) {
                    if let overlapLayout, overlapLayout.isOverlapping {
                        EventCardStateIndicatorView(
                            overlapLayout: overlapLayout,
                            color: accentColor,
                            colorScheme: colorScheme,
                            isExpanded: isSeparated
                        )
                        .padding(.top, 9)
                        .padding(.trailing, 10)
                    }
                }
                .opacity(isDimmed ? DayView.Layout.overlapDimmedOpacity : 1)
        }
    }

    private struct EventCardStateIndicatorView: View {
        let overlapLayout: DayEventOverlapLayout
        let color: Color
        let colorScheme: ColorScheme
        let isExpanded: Bool

        private var collapsedLayerCount: Int {
            min(max(overlapLayout.groupSize, 2), 3)
        }

        private var expandedNodeCount: Int {
            min(max(overlapLayout.groupSize, 2), 4)
        }

        private var highlightedNodeIndex: Int {
            min(overlapLayout.orderIndex, expandedNodeCount - 1)
        }

        private var chipBackground: Color {
            colorScheme == .light
            ? Color(UIColor.systemBackground).opacity(0.82)
            : Color(UIColor.secondarySystemBackground).opacity(0.64)
        }

        var body: some View {
            Group {
                if isExpanded {
                    VStack(spacing: 3) {
                        ForEach(0..<expandedNodeCount, id: \.self) { index in
                            Capsule()
                                .fill(index == highlightedNodeIndex ? color : color.opacity(0.22))
                                .frame(width: index == highlightedNodeIndex ? 10 : 6, height: 4)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(chipBackground)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(color.opacity(0.16), lineWidth: 1)
                            }
                    }
                } else {
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<collapsedLayerCount, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(chipBackground)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(color.opacity(index == 0 ? 0.44 : 0.24), lineWidth: 0.9)
                                }
                                .frame(width: 12, height: 9)
                                .offset(x: CGFloat(index) * 2.4, y: CGFloat(index) * 1.9)
                        }
                    }
                    .frame(width: 18, height: 14, alignment: .topLeading)
                }
            }
            .shadow(
                color: color.opacity(isExpanded ? 0.16 : 0.08),
                radius: isExpanded ? 6 : 3,
                x: 0,
                y: isExpanded ? 3 : 1
            )
            .animation(DayView.Layout.overlapAnimation, value: isExpanded)
            .accessibilityHidden(true)
        }
    }

    private struct EventCardContentView: View {
        let title: String
        let detail: String
        let colorHex: String
        let colorScheme: ColorScheme
        let isCompact: Bool
        let showsOverlapIndicator: Bool
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        private var isRegularWidth: Bool { horizontalSizeClass == .regular }

        private var accentColor: Color {
            Color(hex: colorHex, opacity: colorScheme == .light ? 0.9 : 0.78)
        }

        private var titleFont: Font {
            if isRegularWidth {
                return isCompact ? .headline.weight(.semibold) : .title3.weight(.semibold)
            }
            return isCompact ? .subheadline.weight(.semibold) : .headline.weight(.semibold)
        }

        private var detailFont: Font {
            isRegularWidth ? .subheadline.weight(.medium) : .footnote.weight(.medium)
        }

        private var capsuleWidth: CGFloat {
            if isRegularWidth {
                return isCompact ? 4 : 5
            }
            return isCompact ? 3 : 4
        }

        private var hStackSpacing: CGFloat { isRegularWidth ? 14 : 10 }
        private var vStackSpacing: CGFloat { isRegularWidth ? (isCompact ? 4 : 10) : (isCompact ? 2 : 8) }
        private var horizontalPadding: CGFloat { isRegularWidth ? 18 : DayView.Layout.eventCardHorizontalPadding }
        private var verticalPadding: CGFloat {
            if isRegularWidth {
                return isCompact ? 10 : 14
            }
            return isCompact ? DayView.Layout.eventCardCompactVerticalPadding : DayView.Layout.eventCardVerticalPadding
        }

        var body: some View {
            HStack(alignment: .top, spacing: hStackSpacing) {
                Capsule()
                    .fill(accentColor)
                    .frame(width: capsuleWidth)
                    .padding(.vertical, isCompact ? 4 : 2)

                VStack(alignment: .leading, spacing: vStackSpacing) {
                    Text(title)
                        .font(titleFont)
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.primary)
                        .lineLimit(isCompact ? 1 : 2)
                        .truncationMode(.tail)

                    if !isCompact {
                        Text(detail)
                            .font(detailFont)
                            .fontDesign(.rounded)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .padding(.trailing, showsOverlapIndicator ? (isCompact ? 18 : 24) : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private struct EventCardPreviewView: View {
        let title: String
        let detail: String
        let colorHex: String
        let colorScheme: ColorScheme
        let previewWidth: CGFloat
        let previewHeight: CGFloat

        var body: some View {
            EventCardSurfaceView(colorHex: colorHex, colorScheme: colorScheme, overlapLayout: nil) {
                EventCardContentView(
                    title: title,
                    detail: detail,
                    colorHex: colorHex,
                    colorScheme: colorScheme,
                    isCompact: false,
                    showsOverlapIndicator: false
                )
            }
            .frame(width: previewWidth, height: previewHeight, alignment: .topLeading)
        }
    }

    private func customScheduleDetail(_ info: CustomSchedule) -> String {
        "\(info.begin.formatted(format: "H:mm")) - \(info.end.formatted(format: "H:mm"))・\(info.location)"
    }

    private func scheduleClassroom(_ info: ScheduleInfo) -> String {
        info.schedule.classroom == "." ? "不排教室" : info.schedule.classroom
    }

    private func scheduleDetail(_ info: ScheduleInfo) -> String {
        "\(info.schedule.startTime()) - \(info.schedule.finishTime())・\(scheduleClassroom(info))"
    }

    private func scheduleEventID(_ info: ScheduleInfo) -> String {
        "schedule:\(info.id)"
    }

    private func customScheduleEventID(_ info: CustomSchedule) -> String {
        let fallbackID = "\(info.name)-\(info.begin.timeIntervalSince1970)-\(info.end.timeIntervalSince1970)"
        return "custom:\(info.id.map(String.init) ?? fallbackID)"
    }

    private func scheduleDescriptor(_ info: ScheduleInfo) -> TimedEventDescriptor {
        let height = info.schedule.height()
        let centerY = info.schedule.y()
        return TimedEventDescriptor(
            id: scheduleEventID(info),
            start: centerY - height / 2,
            end: centerY + height / 2
        )
    }

    private func customScheduleDescriptor(_ info: CustomSchedule) -> TimedEventDescriptor {
        let height = info.height()
        let centerY = info.y()
        return TimedEventDescriptor(
            id: customScheduleEventID(info),
            start: centerY - height / 2,
            end: centerY + height / 2
        )
    }

    private func computeOverlapLayouts(for events: [TimedEventDescriptor]) -> [String: DayEventOverlapLayout] {
        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                if lhs.end == rhs.end {
                    return lhs.id < rhs.id
                }
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }

        var result: [String: DayEventOverlapLayout] = [:]
        var currentGroup: [TimedEventDescriptor] = []
        var currentGroupMaxEnd: CGFloat = 0

        func flushCurrentGroup() {
            guard !currentGroup.isEmpty else { return }
            defer {
                currentGroup.removeAll(keepingCapacity: true)
                currentGroupMaxEnd = 0
            }

            guard currentGroup.count > 1 else {
                let event = currentGroup[0]
                result[event.id] = DayEventOverlapLayout(
                    groupID: nil,
                    orderIndex: 0,
                    groupSize: 1,
                    expandedCenter: (event.start + event.end) / 2
                )
                return
            }

            let groupID = "day-overlap:\(currentGroup.map(\.id).joined(separator: "|"))"
            let groupStart = currentGroup.map(\.start).min() ?? 0
            let groupEnd = currentGroup.map(\.end).max() ?? 1
            let groupCenter = (groupStart + groupEnd) / 2
            let totalHeight = currentGroup.reduce(CGFloat(0)) { partialResult, event in
                partialResult + (event.end - event.start)
            } + Layout.overlapStackSpacingRatio * CGFloat(max(currentGroup.count - 1, 0))
            var currentTop = max(0, min(groupCenter - totalHeight / 2, 1 - totalHeight))

            for (index, event) in currentGroup.enumerated() {
                let eventHeight = event.end - event.start
                let expandedCenter = currentTop + eventHeight / 2

                result[event.id] = DayEventOverlapLayout(
                    groupID: groupID,
                    orderIndex: index,
                    groupSize: currentGroup.count,
                    expandedCenter: expandedCenter
                )

                currentTop += eventHeight + Layout.overlapStackSpacingRatio
            }
        }

        for event in sortedEvents {
            guard !currentGroup.isEmpty else {
                currentGroup = [event]
                currentGroupMaxEnd = event.end
                continue
            }

            if event.start < currentGroupMaxEnd {
                currentGroup.append(event)
                currentGroupMaxEnd = max(currentGroupMaxEnd, event.end)
            } else {
                flushCurrentGroup()
                currentGroup = [event]
                currentGroupMaxEnd = event.end
            }
        }

        flushCurrentGroup()
        return result
    }

    private func eventCardPlacement(for overlapLayout: DayEventOverlapLayout?, baseYPosition: CGFloat, containerHeight: CGFloat) -> EventCardPlacement {
        let isExpanded = overlapLayout?.groupID != nil && overlapLayout?.groupID == expandedOverlapGroupID
        let isDimmed = expandedOverlapGroupID != nil && !isExpanded

        guard isExpanded, let overlapLayout else {
            return EventCardPlacement(
                yPosition: baseYPosition,
                isSeparated: false,
                isDimmed: isDimmed
            )
        }

        return EventCardPlacement(
            yPosition: overlapLayout.expandedCenter * containerHeight,
            isSeparated: true,
            isDimmed: false
        )
    }

    private func eventCardZIndex(for overlapLayout: DayEventOverlapLayout?, yPosition: CGFloat) -> Double {
        let baseZIndex = Double(yPosition) * 1000

        guard let overlapLayout else {
            return baseZIndex
        }

        if overlapLayout.groupID == expandedOverlapGroupID {
            return 10_000 + baseZIndex + Double(overlapLayout.groupSize - overlapLayout.orderIndex)
        }

        if expandedOverlapGroupID != nil {
            return baseZIndex / 10
        }

        return baseZIndex
    }

    private func collapseExpandedOverlapGroup(animated: Bool = true) {
        guard expandedOverlapGroupID != nil else { return }

        if animated {
            withAnimation(Layout.overlapAnimation) {
                expandedOverlapGroupID = nil
            }
        } else {
            expandedOverlapGroupID = nil
        }
    }

    private func handleEventTap(eventID: String, defaultAction: @escaping () -> Void) {
        guard let overlapLayout = overlapLayoutsByEventID[eventID], overlapLayout.isOverlapping, let groupID = overlapLayout.groupID else {
            if expandedOverlapGroupID != nil {
                collapseExpandedOverlapGroup()
            } else {
                defaultAction()
            }
            return
        }

        guard expandedOverlapGroupID == groupID else {
            withAnimation(Layout.overlapAnimation) {
                expandedOverlapGroupID = groupID
            }
            return
        }

        defaultAction()
    }

    @ViewBuilder
    private func eventCard<MenuContent: View>(
        eventID: String,
        overlapLayout: DayEventOverlapLayout?,
        colorHex: String,
        title: String,
        detail: String,
        cardHeight: CGFloat,
        yPosition: CGFloat,
        containerHeight: CGFloat,
        defaultOnTap: @escaping () -> Void,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) -> some View {
        GeometryReader { geometry in
            let cardWidth = max(geometry.size.width - 4, 1)
            let placement = eventCardPlacement(
                for: overlapLayout,
                baseYPosition: yPosition,
                containerHeight: containerHeight
            )
            let isFocused = overlapLayout?.groupID != nil && overlapLayout?.groupID == expandedOverlapGroupID

            EventCardSurfaceView(
                colorHex: colorHex,
                colorScheme: colorScheme,
                overlapLayout: overlapLayout,
                isSeparated: placement.isSeparated,
                isFocused: isFocused,
                isDimmed: placement.isDimmed
            ) {
                EventCardContentView(
                    title: title,
                    detail: detail,
                    colorHex: colorHex,
                    colorScheme: colorScheme,
                    isCompact: cardHeight < Layout.eventCardCompactThreshold,
                    showsOverlapIndicator: overlapLayout?.isOverlapping == true
                )
            }
                .contentShape(RoundedRectangle(cornerRadius: Layout.eventCardCornerRadius, style: .continuous))
                .contextMenu {
                    menuContent()
                } preview: {
                    EventCardPreviewView(
                        title: title,
                        detail: detail,
                        colorHex: colorHex,
                        colorScheme: colorScheme,
                        previewWidth: min(cardWidth, 340),
                        previewHeight: max(cardHeight, 72)
                    )
                }
                .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
                .position(x: geometry.size.width / 2, y: placement.yPosition)
                .zIndex(eventCardZIndex(for: overlapLayout, yPosition: yPosition))
                .onTapGesture {
                    handleEventTap(eventID: eventID, defaultAction: defaultOnTap)
                }
        }
        .padding([.leading, .trailing], 2)
    }

    @ViewBuilder
    private func customScheduleCards(containerHeight: CGFloat) -> some View {
        ForEach(customSchedules, id: \.id) { info in
            let colorHex = info.color ?? "#5D737E"
            let cardHeight = info.height() * containerHeight

            eventCard(
                eventID: customScheduleEventID(info),
                overlapLayout: overlapLayoutsByEventID[customScheduleEventID(info)],
                colorHex: colorHex,
                title: info.name,
                detail: customScheduleDetail(info),
                cardHeight: cardHeight,
                yPosition: info.y() * containerHeight,
                containerHeight: containerHeight,
                defaultOnTap: { onCustomScheduleTouch(info) }
            ) {
                Button {
                    onCustomScheduleTouch(info)
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
                Button(role: .destructive) {
                    if let id = info.id {
                        Task {
                            do {
                                try await Eloquent.deleteCustomSchedule(id: id)
                                WidgetCenter.shared.reloadAllTimelines()
                            } catch {
                                print(error)
                            }
                        }
                    }
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleCards(containerHeight: CGFloat) -> some View {
        ForEach(schedules, id: \.id) { info in
            let cardHeight = info.schedule.height() * containerHeight

            eventCard(
                eventID: scheduleEventID(info),
                overlapLayout: overlapLayoutsByEventID[scheduleEventID(info)],
                colorHex: info.class_.color,
                title: info.course.name,
                detail: scheduleDetail(info),
                cardHeight: cardHeight,
                yPosition: info.schedule.y() * containerHeight,
                containerHeight: containerHeight,
                defaultOnTap: { onScheduleTouch(info) }
            ) {
                Button {
                    onScheduleTouch(info)
                } label: {
                    Label("查看课程信息", systemImage: "info.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func nowTimeIndicator(containerHeight: CGFloat, nowPosition: CGFloat, hourHeight: CGFloat) -> some View {
        GeometryReader { geometry in
            Divider()
                .frame(height: Layout.dividerThickness)
                .background(Color(UIColor.red))
                .position(
                    x: geometry.size.width / 2,
                    y: containerHeight * nowPosition + (Layout.dividerThickness + hourHeight) / 2
                )
                .zIndex(1)

            Text("\(Date.now.get(.hour)):\(String(Date.now.get(.minute)).leftPadding(toLength: 2, withPad: "0"))")
                .font(.caption2)
                .frame(width: 36, height: 16)
                .background(Color.red)
                .foregroundStyle(Color.white)
                .cornerRadius(4)
                .position(
                    x: -18,
                    y: containerHeight * nowPosition + (Layout.dividerThickness + hourHeight) / 2
                )
        }
    }

    func updateCurrentTime() {
        guard day.isToday() else {
            nowPosition = nil
            return
        }

        let timeTable = CollegeTimeTable[colleges.first!, default: []]
        let (start, finish) = timeTable.getHours()
        let now = Date.now
        let currentHour = now.get(.hour)
        let currentMinute = now.get(.minute)

        guard currentHour >= start && currentHour < finish else {
            nowPosition = nil
            return
        }

        let elapsedMinutes = (currentHour - start) * 60 + currentMinute
        let totalMinutes = max((finish - start) * 60, 1)
        nowPosition = CGFloat(elapsedMinutes) / CGFloat(totalMinutes)
    }

    var body: some View {
        HStack(spacing: 8) {
            let timeTable = CollegeTimeTable[colleges.first!, default: []]
            let (start, finish) = timeTable.getHours()
            let hourSpacing = self.hourSpacing
            let hourHeight = self.hourHeight
            let containerHeight = (hourSpacing + hourHeight) * CGFloat(finish - start)

            HourAxisView(start: start, finish: finish, hourSpacing: hourSpacing, hourHeight: hourHeight)
                .padding([.top, .bottom], Layout.axisVerticalPadding)

            ZStack {
                HourGridView(
                    start: start,
                    finish: finish,
                    containerHeight: containerHeight,
                    dividerColor: hourGridDividerColor,
                    hourSpacing: hourSpacing,
                    hourHeight: hourHeight
                )

                if expandedOverlapGroupID != nil {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            collapseExpandedOverlapGroup()
                        }
                }

                ZStack(alignment: .top) {
                    customScheduleCards(containerHeight: containerHeight)
                    scheduleCards(containerHeight: containerHeight)
                }
                .padding([.leading], Layout.verticalDividerOffset + Layout.dividerThickness / 2)
                .frame(height: containerHeight)

                if let nowPosition {
                    nowTimeIndicator(containerHeight: containerHeight, nowPosition: nowPosition, hourHeight: hourHeight)
                        .zIndex(20_000)
                }
            }
            .padding([.top, .bottom], Layout.axisVerticalPadding)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
        .padding([.leading, .trailing], Layout.viewHorizontalPadding)
        .frame(maxWidth: .infinity)
        .onReceive(timer) { t in
            updateCurrentTime()
        }
        .task {
            updateCurrentTime()
        }
        .onChange(of: schedules) {
            collapseExpandedOverlapGroup(animated: false)
        }
        .onChange(of: customSchedules) {
            collapseExpandedOverlapGroup(animated: false)
        }
        .animation(Layout.overlapAnimation, value: expandedOverlapGroupID)
        .animation(.easeInOut, value: schedules)
        .animation(.easeInOut, value: customSchedules)
    }
}

struct WeekScheduleTimeSlots: View {
    let college: College

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var slotHeight: CGFloat {
        ScheduleGridMetrics.weekSlotHeight(isPad: isPadDevice)
    }

    var body: some View {
        let timeSlots = CollegeTimeTable[college]!

        VStack(spacing: 1.2) {
            ForEach(timeSlots, id: \.id) { timeSlot in
                VStack {
                    if timeSlot.description == nil {
                        Text("\(timeSlot.id + 1)")
                            .font(.callout)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                            .fontWeight(.medium)
                        VStack(spacing: 0) {
                            Text(timeSlot.start)
                                .font(.caption2)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                            Text(timeSlot.finish)
                                .font(.caption2)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                    } else {
                        Text(timeSlot.description!)
                            .font(.callout)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                            .fontWeight(.medium)
                    }
                }
                .padding(4)
                .frame(height: slotHeight)
            }
        }
    }
}

struct DashedVerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        return path
    }
}

struct WeekScheduleView: View {
    let day: Date
    let colleges: [College]
    let onScheduleTouch: (ScheduleInfo) -> Void
    let onCustomScheduleTouch: (CustomSchedule) -> Void

    @Query<SchedulesRequest> private var schedules: [ScheduleInfo]
    @Query<CustomSchedulesRequest> private var customSchedules: [CustomSchedule]
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("schedule.backgroundImage") private var backgroundImage: URL?
    @AppStorage("schedule.backgroundImage.landscape") private var landscapeBackgroundImage: URL?

    init(day: Date, colleges: [College], onScheduleTouch: @escaping (ScheduleInfo) -> Void, onCustomScheduleTouch: @escaping (CustomSchedule) -> Void) {
        self.day = day
        self.colleges = colleges
        self.onScheduleTouch = onScheduleTouch
        self.onCustomScheduleTouch = onCustomScheduleTouch
        _schedules = Query(constant: SchedulesRequest(colleges: colleges, date: day, isWeek: true))
        _customSchedules = Query(constant: CustomSchedulesRequest(colleges: colleges, date: day, isWeek: true))
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var slotHeight: CGFloat {
        ScheduleGridMetrics.weekSlotHeight(isPad: isPadDevice)
    }

    private var cardCornerRadius: CGFloat { isRegularWidth ? 14 : 12 }
    private var cardHorizontalPadding: CGFloat { isRegularWidth ? 8 : 4 }
    private var cardVerticalPadding: CGFloat { isRegularWidth ? 6 : 4 }
    private var cardOuterPadding: CGFloat { isRegularWidth ? 3 : 2 }
    private var cardTitleFont: Font { isRegularWidth ? .callout.weight(.medium) : .caption.weight(.medium) }
    private var cardSubtitleFont: Font { isRegularWidth ? .footnote : .caption2 }

    private let dividerThickness: CGFloat = 1

    private var hasCustomBackgroundImage: Bool {
        backgroundImage != nil || landscapeBackgroundImage != nil
    }

    private var gridDividerColor: Color {
        scheduleGridDividerColor(hasCustomBackgroundImage: hasCustomBackgroundImage)
    }

    private var verticalDividerStrokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: dividerThickness,
            lineCap: .round,
            dash: hasCustomBackgroundImage ? [4, 6] : [5, 5]
        )
    }

    private func scheduleClassroom(_ info: ScheduleInfo) -> String {
        info.schedule.classroom == "." ? "不排教室" : info.schedule.classroom
    }

    private func customScheduleDetail(_ info: CustomSchedule) -> String {
        "\(info.begin.formatted(format: "H:mm")) - \(info.end.formatted(format: "H:mm"))・\(info.location)"
    }

    private func schedules(for weekday: Int) -> [ScheduleInfo] {
        schedulesByWeekday[weekday, default: []]
    }

    private func customSchedules(for weekday: Int) -> [CustomSchedule] {
        customSchedulesByWeekday[weekday, default: []]
    }

    private var schedulesByWeekday: [Int: [ScheduleInfo]] {
        Dictionary(grouping: schedules, by: { $0.schedule.day })
    }

    private var customSchedulesByWeekday: [Int: [CustomSchedule]] {
        // Convert Foundation weekday (Sun = 1) to 0...6 where Monday is 0.
        Dictionary(grouping: customSchedules, by: { ($0.begin.get(.weekday) + 5) % 7 })
    }

    private func cardHeight(length: Int) -> CGFloat {
        CGFloat(length) * slotHeight + CGFloat(length - 1) * dividerThickness - 4
    }

    private func cardYPosition(periodIndex: Int) -> CGFloat {
        CGFloat(periodIndex) * slotHeight + max(0, CGFloat(periodIndex) - 1) * dividerThickness
    }

    private func customSchedulePlacement(for info: CustomSchedule) -> (height: CGFloat, y: CGFloat)? {
        let displayedSlotCount = info.length()
        guard displayedSlotCount > 0 else { return nil }

        let height = cardHeight(length: displayedSlotCount)
        guard height > 0 else { return nil }

        return (
            height: height,
            y: cardYPosition(periodIndex: info.period())
        )
    }

    @ViewBuilder
    private func horizontalDividers(timeSlotCount: Int) -> some View {
        ForEach(1..<timeSlotCount, id: \.self) { id in
            GeometryReader { geometry in
                Rectangle()
                    .fill(gridDividerColor)
                    .frame(height: dividerThickness)
                    .position(
                        x: geometry.size.width / 2,
                        y: CGFloat(id) * slotHeight + (CGFloat(id) - 1) * dividerThickness + dividerThickness / 2
                    )
            }
        }
    }

    private var verticalDividers: some View {
        ForEach(1...6, id: \.self) { id in
            GeometryReader { geometry in
                DashedVerticalLine()
                    .stroke(gridDividerColor, style: verticalDividerStrokeStyle)
                    .frame(width: dividerThickness)
                    .position(x: CGFloat(id) * geometry.size.width / 7 + dividerThickness / 2, y: geometry.size.height / 2)
            }
        }
    }

    private var weekdayColumns: some View {
        HStack(spacing: 0) {
            ForEach(0...6, id: \.self) { weekday in
                weekdayColumn(for: weekday)
            }
        }
        .frame(maxHeight: .infinity)
        .transition(.opacity)
    }

    private func weekdayColumn(for weekday: Int) -> some View {
        let daySchedules = schedules(for: weekday)
        let dayCustomSchedules = customSchedules(for: weekday)

        return ZStack(alignment: .top) {
            ForEach(daySchedules, id: \.id) { info in
                scheduleCard(for: info)
            }

            ForEach(dayCustomSchedules, id: \.id) { info in
                customScheduleCard(for: info)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scheduleCard(for info: ScheduleInfo) -> some View {
        let classroom = scheduleClassroom(info)
        let height = cardHeight(length: info.schedule.length)
        let y = cardYPosition(periodIndex: info.schedule.periodIndex())

        return weekItemCard(
            title: info.course.name,
            subtitle: classroom,
            previewSubtitle: classroom,
            colorHex: info.class_.color,
            height: height,
            y: y,
            onTap: {
                onScheduleTouch(info)
            }
        ) {
            Button {
                onScheduleTouch(info)
            } label: {
                Label("查看课程信息", systemImage: "info.circle")
            }
        }
    }

    @ViewBuilder
    private func customScheduleCard(for info: CustomSchedule) -> some View {
        if let placement = customSchedulePlacement(for: info) {
            let colorHex = info.color ?? "#5D737E"

            weekItemCard(
                title: info.name,
                subtitle: info.location,
                previewSubtitle: customScheduleDetail(info),
                colorHex: colorHex,
                height: placement.height,
                y: placement.y,
                onTap: {
                    onCustomScheduleTouch(info)
                }
            ) {
                Button {
                    onCustomScheduleTouch(info)
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
                Button(role: .destructive) {
                    if let id = info.id {
                        Task {
                            do {
                                try await Eloquent.deleteCustomSchedule(id: id)
                                WidgetCenter.shared.reloadAllTimelines()
                            } catch {
                                print(error)
                            }
                        }
                    }
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func weekItemPreview(title: String, subtitle: String, colorHex: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)

        return VStack(alignment: .leading, spacing: isRegularWidth ? 8 : 6) {
            Text(title)
                .font(cardTitleFont)
                .foregroundStyle(Color.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(cardSubtitleFont)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.horizontal, isRegularWidth ? 14 : 12)
        .padding(.vertical, isRegularWidth ? 11 : 9)
        .background {
            shape
                .fill(colorScheme == .light ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
                .overlay {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: colorHex, opacity: colorScheme == .light ? 0.28 : 0.42),
                                    Color(hex: colorHex, opacity: colorScheme == .light ? 0.17 : 0.3),
                                    Color(hex: colorHex, opacity: colorScheme == .light ? 0.08 : 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    shape
                        .stroke(
                            Color(hex: colorHex, opacity: colorScheme == .light ? 0.28 : 0.4),
                            lineWidth: 1
                        )
                }
        }
    }

    private func weekItemCard<MenuContent: View>(
        title: String,
        subtitle: String,
        previewSubtitle: String,
        colorHex: String,
        height: CGFloat,
        y: CGFloat,
        onTap: @escaping () -> Void,
        @ViewBuilder contextMenu: @escaping () -> MenuContent
    ) -> some View {
        GeometryReader { geometry in
            let cardShape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)

            cardShape
                .fill(colorScheme == .light ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
                .overlay {
                    cardShape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: colorHex, opacity: colorScheme == .light ? 0.26 : 0.4),
                                    Color(hex: colorHex, opacity: colorScheme == .light ? 0.16 : 0.28),
                                    Color(hex: colorHex, opacity: colorScheme == .light ? 0.08 : 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    cardShape
                        .stroke(
                            Color(hex: colorHex, opacity: colorScheme == .light ? 0.24 : 0.36),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color(hex: colorHex, opacity: colorScheme == .light ? 0.16 : 0.22),
                    radius: colorScheme == .light ? 6 : 4,
                    x: 0,
                    y: colorScheme == .light ? 3 : 2
                )
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading) {
                        Text(title)
                            .font(cardTitleFont)
                            .foregroundStyle(Color.primary)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .layoutPriority(1)

                        Spacer()

                        Text(subtitle)
                            .font(cardSubtitleFont)
                            .foregroundStyle(Color.secondary)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.82)
                            .allowsTightening(true)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .bottomLeading
                            )
                    }
                    .padding(.horizontal, cardHorizontalPadding)
                    .padding(.vertical, cardVerticalPadding)
                }
                .clipShape(cardShape)
                .contentShape(cardShape)
                .contextMenu {
                    contextMenu()
                } preview: {
                    weekItemPreview(title: title, subtitle: previewSubtitle, colorHex: colorHex)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: height)
                .position(x: geometry.size.width / 2, y: y + height / 2 + 1)
                .onTapGesture {
                    onTap()
                }
        }
        .padding(cardOuterPadding)
    }

    var body: some View {
        let timeSlotCount = CollegeTimeTable[colleges.first!]!.count

        ZStack(alignment: .top) {
            horizontalDividers(timeSlotCount: timeSlotCount)
            verticalDividers
            weekdayColumns
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut, value: schedules)
    }
}

struct DayTabView: View {
    // Keep the prefetched page window tight to reduce render work during mode switches.
    private static let initialWindowRadius = 3
    @Binding var selectedDay: Date
    let colleges: [College]
    let baseDay: Date
    let topContentInset: CGFloat
    let bottomContentInset: CGFloat
    let onScheduleTouch: (ScheduleInfo) -> Void
    let onCustomScheduleTouch: (CustomSchedule) -> Void
    let onVerticalContentOffsetChange: (Date, ScheduleVerticalScrollMetrics) -> Void
    let onVerticalScrollPhaseChange: (Date, ScrollPhase) -> Void
    @State private var scrollPosition: ScrollPosition
    @State private var data = Array(-Self.initialWindowRadius...Self.initialWindowRadius)

    private let windowRadius = Self.initialWindowRadius
    private let animatedJumpThreshold = 3

    init(selectedDay: Binding<Date>, colleges: [College], baseDay: Date, topContentInset: CGFloat, bottomContentInset: CGFloat, onScheduleTouch: @escaping (ScheduleInfo) -> Void, onCustomScheduleTouch: @escaping (CustomSchedule) -> Void, onVerticalContentOffsetChange: @escaping (Date, ScheduleVerticalScrollMetrics) -> Void, onVerticalScrollPhaseChange: @escaping (Date, ScrollPhase) -> Void) {
        self._selectedDay = selectedDay
        self.colleges = colleges
        self.baseDay = baseDay
        self.topContentInset = topContentInset
        self.bottomContentInset = bottomContentInset
        self.onScheduleTouch = onScheduleTouch
        self.onCustomScheduleTouch = onCustomScheduleTouch
        self.onVerticalContentOffsetChange = onVerticalContentOffsetChange
        self.onVerticalScrollPhaseChange = onVerticalScrollPhaseChange
        self.scrollPosition = .init(id: selectedDay.wrappedValue.daysSince(baseDay))
    }

    private func recenterData(around position: Int) {
        data = Array(position - windowRadius...position + windowRadius)
    }

    private func syncSelectedDayToScrollPosition() {
        let day = baseDay.addDays(scrollPosition.viewID(type: Int.self)!)
        if !selectedDay.isSameDay(as: day) {
            selectedDay = day
        }
    }

    private func syncScrollToSelectedDay() {
        let id = selectedDay.daysSince(baseDay)
        let currentViewID = scrollPosition.viewID(type: Int.self)!
        guard currentViewID != id else { return }

        if abs(currentViewID - id) < animatedJumpThreshold {
            withAnimation {
                scrollPosition.scrollTo(id: id)
            }
            return
        }

        recenterData(around: id)
        scrollPosition.scrollTo(id: id)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(data, id: \.self) { offset in
                    let day = baseDay.addDays(offset)
                    ScrollView {
                        DayView(day: day, colleges: colleges, onScheduleTouch: onScheduleTouch, onCustomScheduleTouch: onCustomScheduleTouch)
                            .padding(.top, topContentInset)
                            .padding(.bottom, bottomContentInset)
                    }
                    .onScrollGeometryChange(for: ScheduleVerticalScrollMetrics.self) { geometry in
                        ScheduleVerticalScrollMetrics(geometry: geometry)
                    } action: { _, value in
                        onVerticalContentOffsetChange(day, value)
                    }
                    .onScrollPhaseChange { _, newPhase, _ in
                        onVerticalScrollPhaseChange(day, newPhase)
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onChange(of: scrollPosition, {
            syncSelectedDayToScrollPosition()
        })
        .onChange(of: selectedDay) {
            syncScrollToSelectedDay()
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            if newPhase == .idle {
                let dayOffset = scrollPosition.viewID(type: Int.self)!
                recenterData(around: dayOffset)
            }
        }
    }
}

struct WeekScheduleTabView: View {
    // Keep the prefetched page window tight to reduce render work during mode switches.
    private static let initialWindowRadius = 3
    @Binding var selectedDay: Date
    let colleges: [College]
    let baseDay: Date
    let displayMode: DisplayMode
    let onScheduleTouch: (ScheduleInfo) -> Void
    let onCustomScheduleTouch: (CustomSchedule) -> Void
    @State private var scrollPosition: ScrollPosition
    @State private var data = Array(-Self.initialWindowRadius...Self.initialWindowRadius)

    private let windowRadius = Self.initialWindowRadius

    init(selectedDay: Binding<Date>, colleges: [College], baseDay: Date, displayMode: DisplayMode, onScheduleTouch: @escaping (ScheduleInfo) -> Void, onCustomScheduleTouch: @escaping (CustomSchedule) -> Void) {
        self._selectedDay = selectedDay
        self.colleges = colleges
        self.baseDay = baseDay
        self.displayMode = displayMode
        self.onScheduleTouch = onScheduleTouch
        self.onCustomScheduleTouch = onCustomScheduleTouch
        self.scrollPosition = .init(id: selectedDay.wrappedValue.weeksSince(baseDay))
    }

    private func recenterData(around position: Int) {
        data = Array(position - windowRadius...position + windowRadius)
    }

    private func syncSelectedDayToScrollPosition() {
        let day = baseDay.addWeeks(scrollPosition.viewID(type: Int.self)!)
        if !selectedDay.isSameDay(as: day) {
            selectedDay = day
        }
    }

    private func syncScrollToSelectedDay() {
        let id = selectedDay.weeksSince(baseDay)
        let currentViewID = scrollPosition.viewID(type: Int.self)!
        guard currentViewID != id else { return }

        if data.contains(id) {
            withAnimation {
                scrollPosition.scrollTo(id: id)
            }
            return
        }

        recenterData(around: id)
        scrollPosition.scrollTo(id: id)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(data, id: \.self) { offset in
                    let day = baseDay.addWeeks(offset)
                    WeekScheduleView(day: day, colleges: colleges, onScheduleTouch: onScheduleTouch, onCustomScheduleTouch: onCustomScheduleTouch)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onChange(of: scrollPosition, {
            syncSelectedDayToScrollPosition()
        })
        .onChange(of: selectedDay) {
            syncScrollToSelectedDay()
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            if newPhase == .idle {
                let dayOffset = scrollPosition.viewID(type: Int.self)!
                recenterData(around: dayOffset)
            }
        }
    }
}

struct ScheduleView: View {
    @Environment(\.scenePhase) private var scenePhase

    private final class InteractionCache {
        var overlayScrollReferenceOffsetY: CGFloat?
        var dayVerticalScrollMetrics: [Date: ScheduleVerticalScrollMetrics] = [:]
        var weekVerticalScrollMetrics: ScheduleVerticalScrollMetrics = .zero
    }

    @State private var selectedDay: Date = Date.now.startOfDay() // Date.init(timeIntervalSince1970: 1708581600)
    @State private var baseDay: Date = Date.now.startOfWeek()
    @State private var selectedSchedule: ScheduleInfo?
    @State private var activeCustomSchedule: CustomSchedule?
    @AppStorage("collegeId", store: UserDefaults.shared) var collegeId: College = .sjtu
    @AppStorage("showBothCollege", store: UserDefaults.shared) var showBothCollege: Bool = false
    @AppStorage("displayMode") var displayMode: DisplayMode = .day
    @AppStorage("schedule.backgroundImage") var backgroundImage: URL?
    @AppStorage("schedule.backgroundImage.transparency") var backgroundImageTransparency: Double = ScheduleBackgroundEffectConfiguration.defaultTransparency
    @AppStorage("schedule.backgroundImage.blurRadius") var backgroundImageBlurRadius: Double = ScheduleBackgroundEffectConfiguration.defaultBlurRadius
    @AppStorage("schedule.backgroundImage.parallaxEnabled") var backgroundImageParallaxEnabled: Bool = ScheduleBackgroundEffectConfiguration.defaultParallaxEnabled
    @AppStorage("schedule.backgroundImage.landscape") var landscapeBackgroundImage: URL?
    @AppStorage("schedule.backgroundImage.landscape.transparency") var landscapeBackgroundImageTransparency: Double = ScheduleBackgroundEffectConfiguration.defaultTransparency
    @AppStorage("schedule.backgroundImage.landscape.blurRadius") var landscapeBackgroundImageBlurRadius: Double = ScheduleBackgroundEffectConfiguration.defaultBlurRadius
    @AppStorage("schedule.backgroundImage.landscape.parallaxEnabled") var landscapeBackgroundImageParallaxEnabled: Bool = ScheduleBackgroundEffectConfiguration.defaultParallaxEnabled
    @AppStorage("settings.schedule.auto_hide_week_label_overlay") var autoHideWeekLabelOverlay: Bool = true
    @State private var isWeekLabelOverlayVisible = true
    @State private var titleSectionHeight: CGFloat = 0
    @State private var cachedBackgroundImage: UIImage?
    @State private var cachedBackgroundImagePath: String?
    @State private var cachedLandscapeBackgroundImage: UIImage?
    @State private var cachedLandscapeBackgroundImagePath: String?
    @State private var isLandscape = false
    @State private var currentVerticalScrollMetrics: ScheduleVerticalScrollMetrics = .zero
    @State private var currentVerticalScrollPhase: ScrollPhase = .idle
    @State private var interactionCache = InteractionCache()

    private var colleges: [College] {
        (collegeId == .sjtu && showBothCollege) ? [.sjtu, .sjtug] : [collegeId]
    }

    private var weekdaySymbols: [Character] {
        Array("一二三四五六日")
    }

    private var onScheduleTouch: (ScheduleInfo) -> Void {
        { selectedSchedule = $0 }
    }

    private var onCustomScheduleTouch: (CustomSchedule) -> Void {
        { activeCustomSchedule = $0 }
    }

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var useLandscapeBackground: Bool {
        isIPad && isLandscape && cachedLandscapeBackgroundImage != nil
    }

    private var activeBackgroundImage: UIImage? {
        useLandscapeBackground ? cachedLandscapeBackgroundImage : cachedBackgroundImage
    }

    private var hasAnyBackgroundImage: Bool {
        cachedBackgroundImage != nil || (isIPad && cachedLandscapeBackgroundImage != nil)
    }

    private var backgroundEffect: ScheduleBackgroundEffectConfiguration {
        if useLandscapeBackground {
            return .init(
                transparency: landscapeBackgroundImageTransparency,
                blurRadius: landscapeBackgroundImageBlurRadius
            )
        }
        return .init(
            transparency: backgroundImageTransparency,
            blurRadius: backgroundImageBlurRadius
        )
    }

    private var effectiveBackgroundParallaxEnabled: Bool {
        guard activeBackgroundImage != nil else { return false }
        if useLandscapeBackground {
            return landscapeBackgroundImageParallaxEnabled
        }
        return backgroundImageParallaxEnabled
    }
    
    private let weekLabelOverlayHeight: CGFloat = 56
    private let weekLabelOverlayAnimation: Animation = .easeInOut(duration: 0.18)
    private let weekLabelScrollToggleDistance: CGFloat = 18
    private let weekLabelTopContentOffsetTolerance: CGFloat = 0.5
    private let weekLabelBottomRevealGuardDistance: CGFloat = 42
    private let titleBackdropOverflowHeight: CGFloat = 24
    private let scheduleContentFadeHeight: CGFloat = 36
    private let scheduleContentBottomInsetAdjustment: CGFloat = 0
    private let backgroundParallaxScrollFactor: CGFloat = 0.18
    private let backgroundParallaxCanvasPadding: CGFloat = 160

    private var titleBackdropHeight: CGFloat {
        titleSectionHeight + weekLabelOverlayHeight + titleBackdropOverflowHeight
    }

    private var scheduleContentFadeStartY: CGFloat {
        max(titleSectionHeight - 10, 0)
    }

    private var scheduleContentFadeEndY: CGFloat {
        titleSectionHeight + scheduleContentFadeHeight
    }

    private var backgroundParallaxOffsetY: CGFloat {
        guard effectiveBackgroundParallaxEnabled else { return 0 }
        return -currentVerticalScrollMetrics.contentOffsetY * backgroundParallaxScrollFactor
    }

    private func refreshCachedBackgroundImage(for url: URL?) {
        let path = url?.path
        guard cachedBackgroundImagePath != path else { return }
        cachedBackgroundImagePath = path

        guard let path else {
            cachedBackgroundImage = nil
            return
        }

        let loadedImage = UIImage(contentsOfFile: path)
        cachedBackgroundImage = loadedImage
    }

    private func refreshCachedLandscapeBackgroundImage(for url: URL?) {
        let path = url?.path
        guard cachedLandscapeBackgroundImagePath != path else { return }
        cachedLandscapeBackgroundImagePath = path

        guard let path else {
            cachedLandscapeBackgroundImage = nil
            return
        }

        let loadedImage = UIImage(contentsOfFile: path)
        cachedLandscapeBackgroundImage = loadedImage
    }

    private func setWeekLabelOverlayVisibility(_ isVisible: Bool) {
        guard isWeekLabelOverlayVisible != isVisible else { return }
        isWeekLabelOverlayVisible = isVisible
    }

    private func clampedScheduleContentOffsetY(_ metrics: ScheduleVerticalScrollMetrics) -> CGFloat {
        let lowerBound = metrics.topContentOffsetY
        let upperBound = max(metrics.maxContentOffsetY, lowerBound)
        return min(max(metrics.contentOffsetY, lowerBound), upperBound)
    }

    private func isScheduleContentAtTop(_ metrics: ScheduleVerticalScrollMetrics) -> Bool {
        abs(clampedScheduleContentOffsetY(metrics) - metrics.topContentOffsetY) <= weekLabelTopContentOffsetTolerance
    }

    private func isScheduleContentNearBottom(_ metrics: ScheduleVerticalScrollMetrics) -> Bool {
        let upperBound = max(metrics.maxContentOffsetY, metrics.topContentOffsetY)
        let guardStart = max(upperBound - weekLabelBottomRevealGuardDistance, metrics.topContentOffsetY)
        return clampedScheduleContentOffsetY(metrics) >= guardStart
    }

    private func isUserDrivenVerticalScroll(_ phase: ScrollPhase) -> Bool {
        phase == .tracking || phase == .interacting
    }

    private func handleWeekLabelOverlayScroll(metrics: ScheduleVerticalScrollMetrics) {
        guard autoHideWeekLabelOverlay else {
            resetWeekLabelOverlayTracking()
            return
        }

        let contentOffsetY = clampedScheduleContentOffsetY(metrics)

        if isScheduleContentAtTop(metrics) {
            setWeekLabelOverlayVisibility(true)
            interactionCache.overlayScrollReferenceOffsetY = contentOffsetY
            return
        }

        if isScheduleContentNearBottom(metrics) {
            interactionCache.overlayScrollReferenceOffsetY = contentOffsetY
            return
        }

        guard let referenceOffsetY = interactionCache.overlayScrollReferenceOffsetY else {
            interactionCache.overlayScrollReferenceOffsetY = contentOffsetY
            return
        }

        let contentOffsetDeltaY = contentOffsetY - referenceOffsetY
        if contentOffsetDeltaY > weekLabelScrollToggleDistance {
            setWeekLabelOverlayVisibility(false)
            interactionCache.overlayScrollReferenceOffsetY = contentOffsetY
        } else if contentOffsetDeltaY < -weekLabelScrollToggleDistance, isUserDrivenVerticalScroll(currentVerticalScrollPhase) {
            setWeekLabelOverlayVisibility(true)
            interactionCache.overlayScrollReferenceOffsetY = contentOffsetY
        }
    }

    private func syncBackgroundParallaxMetricsToCurrentContext() {
        if displayMode == .day {
            currentVerticalScrollMetrics = interactionCache.dayVerticalScrollMetrics[selectedDay.startOfDay()] ?? .zero
        } else {
            currentVerticalScrollMetrics = interactionCache.weekVerticalScrollMetrics
        }
    }

    private func handleDayVerticalContentOffset(day: Date, metrics: ScheduleVerticalScrollMetrics) {
        interactionCache.dayVerticalScrollMetrics[day.startOfDay()] = metrics
        guard day.isSameDay(as: selectedDay) else { return }
        currentVerticalScrollMetrics = metrics
        handleWeekLabelOverlayScroll(metrics: metrics)
    }

    private func handleDayVerticalScrollPhase(day: Date, phase: ScrollPhase) {
        guard day.isSameDay(as: selectedDay) else { return }
        currentVerticalScrollPhase = phase
    }

    private func handleWeekVerticalScrollPhase(_ phase: ScrollPhase) {
        currentVerticalScrollPhase = phase
    }

    private func resetWeekLabelOverlayTracking(showOverlay: Bool = true) {
        interactionCache.overlayScrollReferenceOffsetY = nil
        currentVerticalScrollPhase = .idle
        guard showOverlay else { return }
        setWeekLabelOverlayVisibility(true)
    }

    @ViewBuilder
    private func scheduleContent(bottomContentInset: CGFloat) -> some View {
        if displayMode == .day {
            DayTabView(
                selectedDay: $selectedDay,
                colleges: colleges,
                baseDay: baseDay,
                topContentInset: titleSectionHeight + weekLabelOverlayHeight,
                bottomContentInset: bottomContentInset,
                onScheduleTouch: onScheduleTouch,
                onCustomScheduleTouch: onCustomScheduleTouch,
                onVerticalContentOffsetChange: handleDayVerticalContentOffset,
                onVerticalScrollPhaseChange: handleDayVerticalScrollPhase
            )
        } else {
            ScrollView {
                HStack(spacing: 0) {
                    WeekScheduleTimeSlots(college: collegeId)
                        .frame(width: weekModeLeading)
                    WeekScheduleTabView(
                        selectedDay: $selectedDay,
                        colleges: colleges,
                        baseDay: baseDay,
                        displayMode: displayMode,
                        onScheduleTouch: onScheduleTouch,
                        onCustomScheduleTouch: onCustomScheduleTouch
                    )
                }
                .padding(.top, titleSectionHeight + weekLabelOverlayHeight + 6)
                .padding(.bottom, bottomContentInset + 6)
            }
            .onScrollGeometryChange(for: ScheduleVerticalScrollMetrics.self) { geometry in
                ScheduleVerticalScrollMetrics(geometry: geometry)
            } action: { _, value in
                interactionCache.weekVerticalScrollMetrics = value
                currentVerticalScrollMetrics = value
                handleWeekLabelOverlayScroll(metrics: value)
            }
            .onScrollPhaseChange { _, newPhase, _ in
                handleWeekVerticalScrollPhase(newPhase)
            }
        }
    }

    @ViewBuilder
    private var scheduleBackground: some View {
        if let activeBackgroundImage {
            GeometryReader { geometry in
                let parallaxOffset = backgroundParallaxOffsetY
                let canvasPadding = effectiveBackgroundParallaxEnabled ? backgroundParallaxCanvasPadding : 0

                ScheduleBackgroundArtwork(
                    image: activeBackgroundImage,
                    effect: backgroundEffect
                )
                    .frame(width: geometry.size.width, height: geometry.size.height + canvasPadding * 2)
                    .offset(y: parallaxOffset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
        } else {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
        }
    }

    private var weekLabelOverlay: some View {
        WeekLabelView(collegeId: collegeId, selectedDay: $selectedDay, displayMode: displayMode)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.interactive())
            }
            .offset(y: isWeekLabelOverlayVisible ? 0 : -10)
            .scaleEffect(isWeekLabelOverlayVisible ? 1 : 0.98, anchor: .top)
            .opacity(isWeekLabelOverlayVisible ? 1 : 0)
            .allowsHitTesting(isWeekLabelOverlayVisible)
            .zIndex(1)
            .compositingGroup()
            .animation(weekLabelOverlayAnimation, value: isWeekLabelOverlayVisible)
            .animation(weekLabelOverlayAnimation, value: selectedDay.startOfDay())
    }

    private var scheduleContentFadeMask: some View {
        GeometryReader { geometry in
            let fadeStart = min(max(scheduleContentFadeStartY, 0), geometry.size.height)
            let fadeEnd = min(max(scheduleContentFadeEndY, fadeStart + 1), geometry.size.height)
            let fadeHeight = max(fadeEnd - fadeStart, 1)

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: fadeStart)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.16), location: 0.22),
                        .init(color: .white.opacity(0.72), location: 0.76),
                        .init(color: .white, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)

                Color.white
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { item in
                Text(String(item.element))
                    .frame(maxWidth: .infinity)
                    .font(.caption2)
            }
        }
    }

    private struct TitleSectionTopBackdrop: View {
        @Environment(\.colorScheme) private var colorScheme
        let useAccentTint: Bool

        private var backdropFadeMask: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.76), location: 0.34),
                    .init(color: .white.opacity(0.22), location: 0.74),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        private var topOverlayOpacity: Double {
            if useAccentTint {
                return colorScheme == .light ? 0.56 : 0.34
            }
            return colorScheme == .light ? 0.48 : 0.28
        }

        private var middleOverlayOpacity: Double {
            if useAccentTint {
                return colorScheme == .light ? 0.16 : 0.1
            }
            return colorScheme == .light ? 0.12 : 0.08
        }

        private var topSheenOpacity: Double {
            colorScheme == .light ? 0.14 : 0.05
        }

        private var accentGlowOpacity: Double {
            colorScheme == .light ? 0.05 : 0.08
        }

        var body: some View {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(backdropFadeMask)

                LinearGradient(
                    stops: [
                        .init(color: Color(UIColor.systemBackground).opacity(topOverlayOpacity), location: 0),
                        .init(color: Color(UIColor.systemBackground).opacity(middleOverlayOpacity), location: 0.36),
                        .init(color: Color(UIColor.systemBackground).opacity(0.08), location: 0.72),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(topSheenOpacity),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 12,
                    endRadius: 280
                )
                .blendMode(.screen)

                if useAccentTint {
                    ZStack {
                        RadialGradient(
                            colors: [
                                Color("AccentColor").opacity(accentGlowOpacity),
                                Color("AccentColor").opacity(colorScheme == .light ? 0.03 : 0.05),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 16,
                            endRadius: 300
                        )

                        LinearGradient(
                            colors: [
                                Color("AccentColor").opacity(colorScheme == .light ? 0.03 : 0.05),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .mask(backdropFadeMask)
                }
            }
            .compositingGroup()
            .allowsHitTesting(false)
        }
    }

    private var topReadableBackdrop: some View {
        TitleSectionTopBackdrop(
            useAccentTint: activeBackgroundImage == nil
        )
        .frame(maxWidth: .infinity)
        .frame(height: max(titleBackdropHeight, 0), alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var titleSection: some View {
        VStack(spacing: 0) {
            ScheduleViewTitle(
                displayMode: $displayMode,
                selectedDay: selectedDay,
                college: collegeId,
                showBothCollege: showBothCollege,
                activeCustomSchedule: $activeCustomSchedule
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            HStack(spacing: 0) {
                if displayMode == .week {
                    Spacer(minLength: weekModeLeading)
                }

                VStack {
                    weekdayHeader
                    WeekTabView(selectedDay: $selectedDay, baseDay: baseDay, displayMode: displayMode)
                        .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let bottomContentInset = max(geometry.safeAreaInsets.bottom + scheduleContentBottomInsetAdjustment, 0)

            ZStack(alignment: .top) {
                scheduleBackground
                    .allowsHitTesting(false)

                scheduleContent(bottomContentInset: bottomContentInset)
                    .ignoresSafeArea(edges: .bottom)
                    .mask(alignment: .top) {
                        scheduleContentFadeMask
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                topReadableBackdrop

                weekLabelOverlay
                    .padding(.top, titleSectionHeight)

                titleSection
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { _, value in
                        titleSectionHeight = value
                    }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
        .animation(.easeInOut(duration: 0.2), value: displayMode)
        .task(id: backgroundImage?.path) {
            refreshCachedBackgroundImage(for: backgroundImage)
        }
        .task(id: landscapeBackgroundImage?.path) {
            refreshCachedLandscapeBackgroundImage(for: landscapeBackgroundImage)
        }
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.size.width > geometry.size.height
        } action: { _, newValue in
            isLandscape = newValue
        }
        .onChange(of: selectedDay) {
            interactionCache.overlayScrollReferenceOffsetY = nil
            currentVerticalScrollPhase = .idle
            if displayMode == .day {
                let key = selectedDay.startOfDay()
                if let metrics = interactionCache.dayVerticalScrollMetrics[key] {
                    currentVerticalScrollMetrics = metrics
                    handleWeekLabelOverlayScroll(metrics: metrics)
                } else {
                    currentVerticalScrollMetrics = .zero
                    // 日期切换后该页若尚未产生纵向滚动回调，先确保 overlay 可见，避免残留隐藏状态。
                    setWeekLabelOverlayVisibility(true)
                }
            }
        }
        .onChange(of: displayMode) {
            syncBackgroundParallaxMetricsToCurrentContext()
            resetWeekLabelOverlayTracking()
        }
        .onChange(of: autoHideWeekLabelOverlay) {
            resetWeekLabelOverlayTracking()
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                resetWeekLabelOverlayTracking(showOverlay: false)
            }
        }
        .sheet(item: $selectedSchedule) { detail in
            NavigationView {
                ClassView(scheduleInfo: detail)
                    .navigationTitle(detail.course.name)
                    .navigationBarTitleDisplayMode(.large)
            }
        }
    }

    private struct WeekLabelView: View {
        var collegeId: College
        @Binding var selectedDay: Date
        let displayMode: DisplayMode
        @Query<SemestersRequest> private var currentSemesters: [Semester]
        @Query<SemestersRequest> private var availableSemesters: [Semester]
        @Environment(\.colorScheme) private var colorScheme

        init(collegeId: College, selectedDay: Binding<Date>, displayMode: DisplayMode) {
            self.collegeId = collegeId
            self._selectedDay = selectedDay
            self.displayMode = displayMode
            _currentSemesters = Query(constant: SemestersRequest(college: collegeId, date: selectedDay.wrappedValue, isWeek: displayMode == .week))
            _availableSemesters = Query(constant: SemestersRequest(college: collegeId))
        }

        private var seasonNames: [String] {
            ["秋", "春", "夏"]
        }

        private var currentSemester: Semester? {
            currentSemesters.first
        }

        private var availableYears: [Int] {
            Array(Set(availableSemesters.map(\.year))).sorted(by: >)
        }

        private func seasonName(for semester: Semester) -> String {
            seasonNames[semester.semester - 1]
        }

        var semesterLabel: String {
            guard let semester = currentSemester else { return "假期" }
            if semester.name != nil { return semester.name! }
            return "\(semester.year) 学年\(seasonName(for: semester))季学期"
        }

        var weekLabel: String {
            guard let semester = currentSemester else { return "" }
            guard let week = semester.displayWeekIndex(for: selectedDay, isWeekContext: displayMode == .week) else { return "" }
            return "第 \(week + 1) 周"
        }
        
        var weeks: [Int] {
            guard let semester = currentSemester else { return [] }
            return Array(1...semester.displayWeekCount())
        }
        
        private var chipFill: Color {
            Color(UIColor.secondarySystemFill).opacity(colorScheme == .dark ? 0.65 : 0.85)
        }

        var body: some View {
            HStack(spacing: 8) {
                Menu {
                    Button {
                        selectedDay = Date.now.startOfDay()
                    } label: {
                        displayMode == .week ?
                        Label("本周", systemImage: "calendar")
                        :
                        Label("今日", systemImage: "calendar.day.timeline.left")
                    }
                    
                    Divider()

                    ForEach(availableYears, id: \.self) { year in
                        Menu {
                            ForEach(availableSemesters.filter { $0.year == year }, id: \.id) { semester in
                                Button {
                                    selectedDay = semester.start_at
                                } label: {
                                    let desc = "\(semester.start_at.formatted(format: "yy/M")) ~ \(semester.end_at.formatted(format: "yy/M"))"
                                    
                                    HStack {
                                        if semester.name != nil {
                                            Text("\(semester.name!) (\(desc))")
                                        } else {
                                            Text("\(seasonName(for: semester))季学期 (\(desc))")
                                        }
                                        if currentSemester?.id == semester.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text("\(String(year)) 学年")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "graduationcap.fill")
                            .font(.caption)
                        Text(semesterLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(chipFill, in: Capsule())
                    .foregroundStyle(Color(UIColor.label))
                }
                
                if currentSemester != nil {
                    Menu {
                        ForEach(weeks, id: \.self) { week in
                            Button {
                                guard let semester = currentSemesters.first else { return }
                                selectedDay = semester.dateForDisplayWeek(week, matchingWeekdayOf: selectedDay)
                            } label: {
                                Text("第\(week)周")
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(weekLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(chipFill, in: Capsule())
                        .foregroundStyle(Color(UIColor.label))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                
                if displayMode == .day {
                    Text(selectedDay.localeWeekday())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(chipFill, in: Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(.subheadline.weight(.semibold))
            .animation(.easeInOut, value: selectedDay)
            .animation(.easeInOut, value: currentSemesters)
            .onChange(of: selectedDay) {
                $currentSemesters.date.wrappedValue = selectedDay
            }
            .onChange(of: collegeId) {
                $currentSemesters.college.wrappedValue = collegeId
            }
            .onChange(of: displayMode) {
                $currentSemesters.isWeek.wrappedValue = displayMode == .week
            }
        }
    }
}

struct CustomScheduleEditorView: View {
    @StateObject private var customScheduleEntry: CustomScheduleEntry
    @Environment(\.dismiss) var dismiss
    @AppStorage("collegeId", store: UserDefaults.shared) var collegeId: College = .sjtu

    private let colleges = [
        CollegeItem(id: College.sjtu, category: "本部", name: "本科"),
        CollegeItem(id: College.sjtug, category: "本部", name: "研究生"),
        CollegeItem(id: College.joint, category: "本部", name: "密西根学院、浦江国际学院"),
        CollegeItem(id: College.shsmu, category: "医学院", name: "医学院"),
    ]
    
    private var categorizedColleges: [(category: String, colleges: [CollegeItem])] {
        let grouped = Dictionary(grouping: colleges, by: \.category)
        let orderedCategories = colleges.reduce(into: [String]()) { result, college in
            if !result.contains(college.category) {
                result.append(college.category)
            }
        }
        
        return orderedCategories.compactMap { category in
            guard let colleges = grouped[category] else {
                return nil
            }
            return (category: category, colleges: colleges)
        }
    }

    private func isBefore(time1: String, time2: String) -> Bool {
        let selfHour = Int(time1.split(separator: ":").first!)!
        let otherHour = Int(time2.split(separator: ":").first!)!
        if selfHour != otherHour {
            return selfHour < otherHour
        }
        let selfMinute = Int(time1.split(separator: ":").last!)!
        let otherMinute = Int(time2.split(separator: ":").last!)!
        return selfMinute < otherMinute
    }

    init(customSchedule: CustomSchedule?) {
        if let customSchedule {
            _customScheduleEntry = .init(wrappedValue: CustomScheduleEntry(schedule: customSchedule))
        } else {
            _customScheduleEntry = .init(wrappedValue: CustomScheduleEntry())
        }
    }
    
    var body: some View {
        let periods = CollegeTimeTable[collegeId]
        let isNameInvalid = customScheduleEntry.name.isEmpty
        let isCollegeUnselected = customScheduleEntry.college == nil
        let isTimeRangeInvalid = customScheduleEntry.begin >= customScheduleEntry.end
        let isCrossDaySchedule = !customScheduleEntry.begin.isSameDay(as: customScheduleEntry.end)
        let isOutsideSchoolPeriod =
            periods != nil &&
            (
                isBefore(time1: periods!.last!.finish, time2: customScheduleEntry.begin.formatted(format: "H:mm"))
                ||
                isBefore(time1: customScheduleEntry.end.formatted(format: "H:mm"), time2: periods!.first!.start)
            )
        let isSaveDisabled =
            isNameInvalid ||
            isCollegeUnselected ||
            isTimeRangeInvalid ||
            isCrossDaySchedule ||
            isOutsideSchoolPeriod
        
        Form {
            Section {
                TextField("标题", text: $customScheduleEntry.name)
                TextField("位置", text: $customScheduleEntry.location)
            }
            .submitLabel(.done)
            
            Section {
                TextField("描述", text: $customScheduleEntry.description, axis: .vertical)
                    .lineLimit(3...5)
            }

            Section {
                DatePicker("开始", selection: $customScheduleEntry.begin, displayedComponents: [.date, .hourAndMinute])
                DatePicker("结束", selection: $customScheduleEntry.end, in: customScheduleEntry.begin..., displayedComponents: [.date, .hourAndMinute])
            }
            .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current)
            
            Section {
                Picker("日历", selection: $customScheduleEntry.college) {
                    ForEach(categorizedColleges, id: \.category) { groupedCollege in
                        Section(groupedCollege.category) {
                            ForEach(groupedCollege.colleges, id: \.id) { college in
                                Text(college.name).tag(college.id as College?)
                            }
                        }
                    }
                }
            }
            
            Section {
                ColorPicker("主题色", selection: Binding(get: {
                    Color(hex: customScheduleEntry.color)
                }, set: { value in
                    if let hex = value.toHex() {
                        customScheduleEntry.color = hex
                    }
                }))
            }
            
            if let id = customScheduleEntry.id {
                Section {
                    Button("删除日程") {
                        Task {
                            do {
                                try await Eloquent.deleteCustomSchedule(id: id)
                                WidgetCenter.shared.reloadAllTimelines()
                                dismiss()
                            } catch {
                                print(error)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task {
                        do {
                            try await Eloquent.saveCustomSchedule(entry: customScheduleEntry)
                            WidgetCenter.shared.reloadAllTimelines()
                            dismiss()
                        } catch {
                            print(error)
                        }
                    }
                }
                .disabled(
                    isSaveDisabled
                )
            }
        }
        .onChange(of: collegeId, initial: true) {
            customScheduleEntry.college = collegeId
        }
    }
}

#Preview {
    ScheduleView()
}
