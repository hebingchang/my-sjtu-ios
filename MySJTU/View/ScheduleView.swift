//
//  ScheduleView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI
import GRDBQuery
import WidgetKit

let weekModeLeading: CGFloat = 48
let timeSlotHeight: CGFloat = 64

struct WeekView: View {
    @Binding var selectedDay: Date
    let week: Date
    let displayMode: DisplayMode

    var body: some View {
        HStack(spacing: 0) {
            let weeks = Array(week.weekDays())
            ForEach(weeks, id: \.self) { date in
                let isCurrentDay = date.isSameDay(as: selectedDay)
                let isToday = date.isSameDay(as: Date())

                var foregroundStyle: Color {
                    if (displayMode == .day && isCurrentDay) {
                        Color(UIColor.systemBackground)
                    } else if (isToday) {
                        Color(UIColor.tintColor)
                    } else {
                        Color(UIColor.label)
                    }
                }

                var background: Color {
                    if (displayMode == .week) {
                        Color(UIColor.clear)
                    } else if (isCurrentDay) {
                        (isToday ? Color(UIColor.tintColor) : Color(UIColor.label))
                    } else {
                        Color(UIColor.clear)
                    }
                }

                Text(String(date.get(.day).day!))
                .frame(maxWidth: .infinity)
                .font(.title3)
                .fontWeight((displayMode == .day && isCurrentDay) ? .medium : .regular)
                .foregroundStyle(foregroundStyle)
                .padding(8)
                .background(background)
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
    @Binding var displayMode: DisplayMode
    @EnvironmentObject var progressor: Progressor
    @EnvironmentObject private var appConfig: AppConfig

    var selectedDay: Date
    var college: College
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var showAlert = false
    @State private var presentAccountPage = false
    @State private var alertError: ImportError?
    
    var body: some View {
        HStack {
            Text(selectedDay.localeMonth())
                .font(.largeTitle.bold())

            Spacer()

            HStack(spacing: 20) {
                Menu {
                    Picker(selection: $displayMode, label: Text("")) {
                        Label("单日", systemImage: "calendar.day.timeline.left").tag(DisplayMode.day)
                        Label("一周", systemImage: "calendar").tag(DisplayMode.week)
                    }
                } label: {
                    Image(systemName: displayMode == .day ? "calendar.day.timeline.left" : "calendar")
                        .font(.title2)
                }
                
                Menu {
                    if appConfig.appStatus == .review {
                        Button("导入日程", systemImage: "square.and.arrow.down") {
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
                                        alertError = .invalidSemester
                                        showAlert.toggle()
                                    }
                                }
                            } catch {
                                print(error)
                            }
                        }
                    } else if college == .sjtu {
                        Button("从教学信息服务网导入", systemImage: "square.and.arrow.down") {
                            let account = accounts.first {
                                $0.provider == .jaccount
                            }
                            
                            if let account {
                                do {
                                    let semester = try Eloquent.getSemester(college: college, date: selectedDay)
                                    if let semester {
                                        Task {
                                            do {
                                                progressor.progress = Progress(description: "正在初始化", value: 0)
                                                let api = SJTUOpenAPI(tokens: account.tokens)
                                                progressor.progress = Progress(description: "正在同步日程", value: 0.1)
                                                let schedules = try await api.getSchedules(semester: semester)
                                                progressor.progress = Progress(description: "正在导入日程", value: 0.6)
                                                try await Eloquent.insertSchedules(semester: semester, college: college, schedules: schedules, deleteExisting: true)
                                                 WidgetCenter.shared.reloadAllTimelines()
                                                progressor.progress = Progress(description: "导入日程完成", value: 1)
                                            } catch {
                                                progressor.progress = Progress(description: "导入日程失败", value: -1)
                                            }
                                        }
                                    } else {
                                        alertError = .invalidSemester
                                        showAlert.toggle()
                                    }
                                } catch {
                                    alertError = .internalError
                                    showAlert.toggle()
                                }
                            } else {
                                alertError = .invalidAccount
                                showAlert.toggle()
                            }
                        }
                    } else if college == .sjtug {
                        Button("从研究生选课系统导入", systemImage: "square.and.arrow.down") {
                            let account = accounts.first {
                                $0.provider == .jaccount
                            }
                            
                            if let account {
                                do {
                                    let semester = try Eloquent.getSemester(college: college, date: selectedDay)
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
                                                try await Eloquent.insertSchedules(semester: semester, college: college, schedules: schedules, deleteExisting: true)
                                                WidgetCenter.shared.reloadAllTimelines()
                                                progressor.progress = Progress(description: "导入日程完成", value: 1)
                                            } catch {
                                                print(error)
                                                progressor.progress = Progress(description: "导入日程失败", value: -1)
                                            }
                                        }
                                    } else {
                                        alertError = .invalidSemester
                                        showAlert.toggle()
                                    }
                                } catch {
                                    alertError = .internalError
                                    showAlert.toggle()
                                }
                            } else {
                                alertError = .invalidAccount
                                showAlert.toggle()
                            }
                        }
                    } else if college == .shsmu {
                        Button("从医学院教务系统导入", systemImage: "square.and.arrow.down") {
                            let account = accounts.first {
                                $0.provider == .shsmu
                            }
                            
                            if let account {
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
                                                    alertError = .sessionExpired
                                                    showAlert.toggle()
                                                    return
                                                }
                                                
                                                progressor.progress = Progress(description: "正在同步日程", value: 0.2)
                                                let bizSchedules = try await api.getSchedules(semester: semester)
                                                var schedules: [CourseClassSchedule] = []
                                                for (index, schedule) in bizSchedules.enumerated() {
                                                    progressor.progress = Progress(description: "正在获取课程信息 \(index+1)/\(bizSchedules.count)", value: 0.4 + (0.8 - 0.4) * Float(index) / Float(bizSchedules.count))
                                                    schedules.append(try await api.getCourseInfo(schedule: schedule))
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
                                        alertError = .invalidSemester
                                        showAlert.toggle()
                                    }
                                } catch {
                                    alertError = .internalError
                                    showAlert.toggle()
                                }
                            } else {
                                alertError = .invalidAccount
                                showAlert.toggle()
                            }
                        }
                    }
                    Button("添加自定义日程", systemImage: "plus") {
                        alertError = .todo
                        showAlert.toggle()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                }
                .sheet(isPresented: $presentAccountPage) {
                    NavigationStack {
                        AccountView(provider: college.provider!)
                            .navigationTitle("\(college.provider!.descriptionShort)账户")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .alert(alertError == .todo ? "暂时无法添加日程" : "暂时无法导入日程", isPresented: $showAlert, presenting: alertError) { detail in
                    if detail == .sessionExpired {
                        Button("前往设置") {
                            presentAccountPage = true
                        }
                        Button("以后", role: .cancel) {
                            showAlert = false
                        }
                    } else if detail == .invalidAccount {
                        Button {
                            presentAccountPage = true
                        } label: {
                            Text("前往设置")
                        }
                        Button("以后", role: .cancel) {
                            showAlert = false
                        }
                    }
                } message: { detail in
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
            }
        }
    }
}

struct WeekTabView: View {
    @Binding var selectedDay: Date
    let baseDay: Date
    let displayMode: DisplayMode
    @State private var scrollPosition: ScrollPosition
    @State private var data = Array(-5...5)

    init(selectedDay: Binding<Date>, baseDay: Date, displayMode: DisplayMode) {
        self._selectedDay = selectedDay
        self.baseDay = baseDay
        self.displayMode = displayMode
        self.scrollPosition = .init(id: selectedDay.wrappedValue.weeksSince(baseDay))
    }


    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(data, id: \.self) { offset in
                    let week = baseDay.addWeeks(offset)
                    WeekView(selectedDay: $selectedDay, week: week, displayMode: displayMode)
                        .frame(width: UIScreen.main.bounds.width - (displayMode == .week ? weekModeLeading : 0))
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
            let id = selectedDay.weeksSince(baseDay)
            let position = scrollPosition.viewID(type: Int.self)!

            if id != position {
                if data.contains(where: { $0 == id }) {
                    withAnimation {
                        self.scrollPosition.scrollTo(id: id)
                    }
                } else {
                    data = Array(id - 5...id + 5)
                    self.scrollPosition.scrollTo(id: id)
                }
            }
        }
        .onChange(of: scrollPosition) {
            let position = scrollPosition.viewID(type: Int.self)!

            if position != selectedDay.weeksSince(baseDay) {
                selectedDay = selectedDay.addWeeks(position - selectedDay.weeksSince(baseDay))
            }
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            let position = scrollPosition.viewID(type: Int.self)!

            if newPhase == .idle {
                data = Array(position - 5...position + 5)
            }
        }
        .frame(height: 40)
    }
}

struct DayView: View {
    let day: Date
    let college: College
    let onScheduleTouch: (ScheduleInfo) -> Void
    
    @Query<SchedulesRequest> private var schedules: [ScheduleInfo]
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @State private var nowPosition: CGFloat?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(day: Date, college: College, onScheduleTouch: @escaping (ScheduleInfo) -> Void) {
        self.day = day
        self.college = college
        self.onScheduleTouch = onScheduleTouch
        _schedules = Query(constant: SchedulesRequest(college: college, date: day))
    }

    func updateCurrentTime() {
        if day.isToday() {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"

            let timeTable = CollegeTimeTable[college, default: []]
            let (start, finish) = timeTable.getHours()
            let now = Date.now

            if now.get(.hour) >= start && now.get(.hour) < finish {
                let timeTableStartTime = formatter.date(from: "\(start):00")!
                let timeTableEndTime = formatter.date(from: "\(finish):00")!
                let nowTime = formatter.date(from: "\(now.get(.hour)):\(now.get(.minute))")!

                nowPosition = nowTime.timeIntervalSince(timeTableStartTime) / timeTableEndTime.timeIntervalSince(timeTableStartTime)
            } else {
                nowPosition = nil
            }
        }
    }

    var body: some View {
        let hourSpacing: CGFloat = 20
        let hourHeight: CGFloat = 20
        let hourFontSize: CGFloat = 14
        let viewVerticalPadding: CGFloat = 14
        let hourHorizontalPadding: CGFloat = 16
        let dividerThickness: CGFloat = 1.2
        let verticalDividerOffset: CGFloat = 12.6

        HStack(spacing: 8) {
            let timeTable = CollegeTimeTable[college, default: []]
            let (start, finish) = timeTable.getHours()

            VStack(alignment: .trailing, spacing: hourSpacing) {
                ForEach(start...finish, id: \.self) { hour in
                    Text("\(hour):00")
                        .frame(height: hourHeight)
                        .font(.system(size: hourFontSize, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
            .padding([.top, .bottom], hourHorizontalPadding)

            ZStack {
                VStack(alignment: .trailing, spacing: hourSpacing) {
                    ForEach(start...finish, id: \.self) { hour in
                        VStack {
                            Divider()
                                .frame(height: dividerThickness)
                                .background(Color(UIColor.systemGray6))
                        }
                        .frame(height: hourHeight)
                    }
                }

                let containerHeight = (hourSpacing + hourHeight) * CGFloat(finish - start)

                Divider()
                    .frame(width: dividerThickness, height: containerHeight)
                    .background(Color(UIColor.systemGray6))
                    .position(x: verticalDividerOffset, y: (hourHeight + dividerThickness + containerHeight) / 2)
                
                ZStack(alignment: .top) {
                    ForEach(schedules, id: \.schedule.period) { info in
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(hex: info.class_.color, opacity: 0.1), lineWidth: 1)
                            .fill(colorScheme == .light ? Color.white : Color.black)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: info.class_.color, opacity: colorScheme == .light ? 0.2 : 0.6))
                                .overlay(alignment: .topLeading) {
                                    if info.schedule.height() * containerHeight < 60 {
                                        VStack(alignment: .leading) {
                                            Text(info.course.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                        }
                                        .padding([.leading, .trailing], 12)
                                        .frame(maxHeight: .infinity)
                                    } else {
                                        VStack(alignment: .leading) {
                                            Text(info.course.name)
                                                .font(.headline)
                                            Spacer()
                                            Text("\(info.schedule.startTime()) - \(info.schedule.finishTime())・\(info.schedule.classroom == "." ? "不排教室" : info.schedule.classroom)")
                                                .font(.subheadline)
                                                .foregroundColor(Color(UIColor.secondaryLabel))
                                        }
                                        .padding([.leading, .trailing], 12)
                                        .padding([.top, .bottom], 10)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contextMenu {
                                    Button {
                                        onScheduleTouch(info)
                                    } label: {
                                        Label("查看课程信息", systemImage: "info.circle")
                                    }
                                } preview: {
                                    VStack(alignment: .leading) {
                                        Text(info.course.name)
                                            .font(.headline)
                                        Text("\(info.schedule.startTime()) - \(info.schedule.finishTime())・\(info.schedule.classroom == "." ? "不排教室" : info.schedule.classroom)")
                                            .font(.subheadline)
                                            .foregroundColor(Color(UIColor.secondaryLabel))
                                    }
                                    .padding([.leading, .trailing], 12)
                                    .padding([.top, .bottom], 10)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color(hex: info.class_.color, opacity: colorScheme == .light ? 0.2 : 0.6))
                                    }
                                }
                            }
                            .frame(height: info.schedule.height() * containerHeight)
                            .position(x: geometry.size.width / 2, y: info.schedule.y() * containerHeight)
                            .onTapGesture {
                                onScheduleTouch(info)
                            }
                        }
                        .padding([.leading, .trailing], 2)
                    }
                }
                .padding([.leading], verticalDividerOffset + dividerThickness / 2)
                .frame(height: containerHeight)
                
                if let nowPosition {
                    GeometryReader { geometry in
                        Divider()
                            .frame(height: dividerThickness)
                            .background(Color(UIColor.red))
                            .position(x: geometry.size.width / 2, y: containerHeight * nowPosition + (dividerThickness + hourHeight) / 2)
                            .zIndex(1)

                        Text("\(Date.now.get(.hour)):\(String(Date.now.get(.minute)).leftPadding(toLength: 2, withPad: "0"))")
                            .font(.caption2)
                            .frame(width: 36, height: 16)
                            .background(Color.red)
                            .foregroundStyle(Color.white)
                            .cornerRadius(4)
                            .position(x: -18, y: containerHeight * nowPosition + (dividerThickness + hourHeight) / 2)
                    }
                }
            }
            .padding([.top, .bottom], hourHorizontalPadding)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
        .padding([.leading, .trailing], viewVerticalPadding)
        .frame(maxWidth: .infinity)
        .onReceive(timer) { t in
            updateCurrentTime()
        }
        .task {
            updateCurrentTime()
        }
        .animation(.easeInOut, value: schedules)
    }
}

struct WeekScheduleTimeSlots: View {
    let college: College

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
                .frame(height: timeSlotHeight)
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
    let college: College
    let onScheduleTouch: (ScheduleInfo) -> Void
    
    @Query<SchedulesRequest> private var schedules: [ScheduleInfo]
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    init(day: Date, college: College, onScheduleTouch: @escaping (ScheduleInfo) -> Void) {
        self.day = day
        self.college = college
        self.onScheduleTouch = onScheduleTouch
        _schedules = Query(constant: SchedulesRequest(college: college, date: day, isWeek: true))
    }

    var body: some View {
        let timeSlots = CollegeTimeTable[college]!
        let dividerThickness: CGFloat = 1

        ZStack(alignment: .top) {
            ForEach(1..<timeSlots.count, id: \.self) { id in
                GeometryReader { geometry in
                    Divider()
                        .frame(height: dividerThickness)
                        .background(Color(UIColor.systemGray6).opacity(0.4))
                        .position(x: geometry.size.width / 2, y: CGFloat(id) * timeSlotHeight + (CGFloat(id) - 1) * dividerThickness + dividerThickness / 2)
                }
            }

            ForEach(1...6, id: \.self) { id in
                GeometryReader { geometry in
                    DashedVerticalLine()
                        .stroke(Color(UIColor.systemGray5), style: StrokeStyle(lineWidth: dividerThickness, dash: [5]))
                        .frame(width: dividerThickness)
                        .position(x: CGFloat(id) * geometry.size.width / 7 + dividerThickness / 2, y: geometry.size.height / 2)
                }
            }

            HStack(spacing: 0) {
                ForEach(0...6, id: \.self) { weekday in
                    ZStack(alignment: .top) {
                        let daySchedules = schedules.filter {
                            $0.schedule.day == weekday
                        }

                        ForEach(daySchedules, id: \.schedule.period) { info in
                            GeometryReader { geometry in
                                let height: CGFloat = CGFloat(info.schedule.length) * timeSlotHeight + CGFloat(info.schedule.length - 1) * dividerThickness - 4
                                let y: CGFloat = CGFloat(info.schedule.period) * timeSlotHeight + max(0, CGFloat(info.schedule.period) - 1) * dividerThickness

                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: info.class_.color, opacity: 0.1), lineWidth: 1)
                                .fill(colorScheme == .light ? Color.white : Color.black)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: info.class_.color, opacity: colorScheme == .light ? 0.2 : 0.6))
                                    .overlay(alignment: .topLeading) {
                                        VStack(alignment: .leading) {
                                            Text(info.course.name)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text("\(info.schedule.classroom == "." ? "不排教室" : info.schedule.classroom)")
                                                .font(.caption2)
                                                .foregroundColor(Color(UIColor.secondaryLabel))
                                        }
                                        .padding([.leading, .trailing], 4)
                                        .padding([.top, .bottom], 5)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contextMenu {
                                        Button {
                                            onScheduleTouch(info)
                                        } label: {
                                            Label("查看课程信息", systemImage: "info.circle")
                                        }
                                    } preview: {
                                        VStack(alignment: .leading) {
                                            Text(info.course.name)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            Text("\(info.schedule.classroom == "." ? "不排教室" : info.schedule.classroom)")
                                                .font(.caption2)
                                                .foregroundColor(Color(UIColor.secondaryLabel))
                                        }
                                        .padding([.leading, .trailing], 12)
                                        .padding([.top, .bottom], 8)
                                        .background {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color(hex: info.class_.color, opacity: colorScheme == .light ? 0.2 : 0.6))
                                        }
                                    }
                                }
                                .frame(height: height)
                                .position(x: geometry.size.width / 2, y: y + height / 2 + 1)
                                .onTapGesture {
                                    onScheduleTouch(info)
                                }
                            }
                            .padding(2)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut, value: schedules)
    }
}

struct DayTabView: View {
    @Binding var selectedDay: Date
    let collegeId: College
    let baseDay: Date
    let displayMode: DisplayMode
    let onScheduleTouch: (ScheduleInfo) -> Void
    @State private var scrollPosition: ScrollPosition
    @State private var data = Array(-7...7)

    init(selectedDay: Binding<Date>, collegeId: College, baseDay: Date, displayMode: DisplayMode, onScheduleTouch: @escaping (ScheduleInfo) -> Void) {
        self._selectedDay = selectedDay
        self.collegeId = collegeId
        self.baseDay = baseDay
        self.displayMode = displayMode
        self.onScheduleTouch = onScheduleTouch
        self.scrollPosition = .init(id: selectedDay.wrappedValue.daysSince(baseDay))
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(data, id: \.self) { offset in
                    let day = baseDay.addDays(offset)
                    ScrollView {
                        DayView(day: day, college: collegeId, onScheduleTouch: onScheduleTouch)
                    }
                    .frame(width: UIScreen.main.bounds.width)
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
            let day = baseDay.addDays(scrollPosition.viewID(type: Int.self)!)
            if !selectedDay.isSameDay(as: day) {
                selectedDay = day
            }
        })
        .onChange(of: selectedDay) {
            let id = selectedDay.daysSince(baseDay)
            let currentViewID = scrollPosition.viewID(type: Int.self)!

            if currentViewID != id {
                if abs(currentViewID - id) < 3 {
                    withAnimation {
                        scrollPosition.scrollTo(id: id)
                    }
                } else {
                    data = Array(id - 7...id + 7)
                    scrollPosition.scrollTo(id: id)
                }
            }
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            if newPhase == .idle {
                let dayOffset = scrollPosition.viewID(type: Int.self)!
                data = Array(dayOffset - 7...dayOffset + 7)
            }
        }
    }
}

struct WeekScheduleTabView: View {
    @Binding var selectedDay: Date
    let collegeId: College
    let baseDay: Date
    let displayMode: DisplayMode
    let onScheduleTouch: (ScheduleInfo) -> Void
    @State private var scrollPosition: ScrollPosition
    @State private var data = Array(-5...5)

    init(selectedDay: Binding<Date>, collegeId: College, baseDay: Date, displayMode: DisplayMode, onScheduleTouch: @escaping (ScheduleInfo) -> Void) {
        self._selectedDay = selectedDay
        self.collegeId = collegeId
        self.baseDay = baseDay
        self.displayMode = displayMode
        self.onScheduleTouch = onScheduleTouch
        self.scrollPosition = .init(id: selectedDay.wrappedValue.weeksSince(baseDay))
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(data, id: \.self) { offset in
                    let day = baseDay.addWeeks(offset)
                    WeekScheduleView(day: day, college: collegeId, onScheduleTouch: onScheduleTouch)
                        .frame(width: UIScreen.main.bounds.width - (displayMode == .week ? weekModeLeading : 0))
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
            let day = baseDay.addWeeks(scrollPosition.viewID(type: Int.self)!)
            if !selectedDay.isSameDay(as: day) {
                selectedDay = day
            }
        })
        .onChange(of: selectedDay) {
            let id = selectedDay.weeksSince(baseDay)
            let currentViewID = scrollPosition.viewID(type: Int.self)!

            if currentViewID != id {
                if data.contains(where: { $0 == id }) {
                    withAnimation {
                        self.scrollPosition.scrollTo(id: id)
                    }
                } else {
                    data = Array(id - 5...id + 5)
                    self.scrollPosition.scrollTo(id: id)
                }
            }
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            if newPhase == .idle {
                let dayOffset = scrollPosition.viewID(type: Int.self)!
                data = Array(dayOffset - 5...dayOffset + 5)
            }
        }
    }
}

struct ScheduleView: View {
    @State private var selectedDay: Date = Date.now.startOfDay() // Date.init(timeIntervalSince1970: 1708581600)
    @State private var baseDay: Date = Date.now.startOfWeek()
    @State private var lastHostingView: UIView!
    @State private var selectedSchedule: ScheduleInfo?
    @AppStorage("collegeId", store: UserDefaults.shared) var collegeId: College = .sjtu
    @AppStorage("displayMode") var displayMode: DisplayMode = .day
    @AppStorage("schedule.headerImage") var headerImage: URL?

    var body: some View {
        let onScheduleTouch: (ScheduleInfo) -> Void = { info in
            selectedSchedule = info
        }

        VStack(spacing: 0) {
            VStack {
                ScheduleViewTitle(displayMode: $displayMode, selectedDay: selectedDay, college: collegeId)
                    .padding()
                
                HStack(spacing: 0) {
                    if displayMode == .week {
                        Spacer(minLength: weekModeLeading)
                    }
                    
                    VStack {
                        HStack(spacing: 0) {
                            let weekdays = Array("一二三四五六日".enumerated())
                            ForEach(weekdays, id: \.offset) { c in
                                Text(String(c.element))
                                    .frame(maxWidth: .infinity)
                                    .font(.caption2)
                            }
                        }
                        
                        if displayMode == .day {
                            WeekTabView(selectedDay: $selectedDay, baseDay: baseDay, displayMode: .day)
                                .padding(.bottom, 6)
                        } else {
                            WeekTabView(selectedDay: $selectedDay, baseDay: baseDay, displayMode: .week)
                                .padding(.bottom, 6)
                        }
                    }
                }
            }
            .if(headerImage != nil) {
                $0.background {
                    AsyncImage(url: headerImage!) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .overlay {
                        Color(UIColor.systemBackground).opacity(0.8)
                    }
                    .ignoresSafeArea()
                }
            }
            .if(headerImage == nil) {
                $0.background(Color(UIColor.systemGray6))
            }
            
            Divider().frame(height: 1).background(Color(UIColor.systemGray6))
            
            WeekLabelView(collegeId: collegeId, selectedDay: $selectedDay, displayMode: displayMode)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground))
            Divider().frame(height: 1).background(Color(UIColor.systemGray6))

            if displayMode == .day {
                DayTabView(selectedDay: $selectedDay, collegeId: collegeId, baseDay: baseDay, displayMode: displayMode, onScheduleTouch: onScheduleTouch)
            } else {
                ScrollView {
                    HStack(spacing: 0) {
                        WeekScheduleTimeSlots(college: collegeId)
                            .frame(width: weekModeLeading)
                        WeekScheduleTabView(selectedDay: $selectedDay, collegeId: collegeId, baseDay: baseDay, displayMode: displayMode, onScheduleTouch: onScheduleTouch)
                    }
                    .padding([.top, .bottom], 6)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
        .animation(.easeInOut(duration: 0.2), value: displayMode)
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

        init(collegeId: College, selectedDay: Binding<Date>, displayMode: DisplayMode) {
            self.collegeId = collegeId
            self._selectedDay = selectedDay
            self.displayMode = displayMode
            _currentSemesters = Query(constant: SemestersRequest(college: collegeId, date: selectedDay.wrappedValue))
            _availableSemesters = Query(constant: SemestersRequest(college: collegeId))
        }
        
        var semesterLabel: String {
            if currentSemesters.count == 0 {
                return "假期"
            } else {
                let semester = currentSemesters.first!
                return "\(semester.year) 学年\(["秋", "春", "夏"][semester.semester - 1])季学期"
            }
        }

        var weekLabel: String {
            if currentSemesters.count == 0 {
                return displayMode == .week ? "" : "・\(selectedDay.localeWeekday())"
            } else {
                let semester = currentSemesters.first!
                let description = "・第 \(selectedDay.weeksSince(semester.start_at) + 1) 周"
                return displayMode == .day ? "\(description) \(selectedDay.localeWeekday())" : description
            }
        }

        var body: some View {
            HStack(spacing: 0) {
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

                    ForEach(Array(Set(availableSemesters.map(\.year))).sorted(by: { $0 > $1 }), id: \.self) { year in
                        Menu {
                            ForEach(availableSemesters.filter { $0.year == year }, id: \.id) { semester in
                                Button {
                                    selectedDay = semester.start_at
                                } label: {
                                    HStack {
                                        Text("\(["秋", "春", "夏"][semester.semester - 1])季学期")
                                        if currentSemesters.first?.id == semester.id {
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
                    Text(semesterLabel)
                        .foregroundStyle(Color(UIColor.label))
                        .lineLimit(1)
                        .fixedSize()
                }
                
                Text(weekLabel)
            }
            .font(.callout)
            .fontWeight(.medium)
            .padding(EdgeInsets.init(top: 6, leading: 0, bottom: 6, trailing: 0))
            .animation(.easeInOut, value: selectedDay)
            .animation(.easeInOut, value: currentSemesters)
            .onChange(of: selectedDay) {
                $currentSemesters.date.wrappedValue = selectedDay
            }
            .onChange(of: collegeId) {
                $currentSemesters.college.wrappedValue = collegeId
            }
        }
    }
}

#Preview {
    ScheduleView()
}
