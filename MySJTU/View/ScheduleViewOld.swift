////
////  ScheduleView.swift
////  MySJTU
////
////  Created by boar on 2024/09/28.
////
//
//import SwiftUI
//
//struct WeekView: View {
//    @Binding var selectedDay: Date
//    let week: Date
//
//    var body: some View {
//        HStack(spacing: 0) {
//            let weeks = Array(week.weekDays())
//            ForEach(weeks, id: \.self) { date in
//                let isCurrentDay = date.isSameDay(as: selectedDay)
//                let isToday = date.isSameDay(as: Date())
//
//                let foregroundStyle = isCurrentDay ? Color(UIColor.systemBackground) : (isToday ? Color(UIColor.tintColor) : Color(UIColor.label))
//                let background = isCurrentDay ? (isToday ? Color(UIColor.tintColor) : Color(UIColor.label)) : Color(UIColor.clear)
//
//                Text(String(date.get(.day).day!))
//                    .frame(maxWidth: .infinity)
//                    .font(.title3)
//                    .fontWeight(isCurrentDay ? .medium : .regular)
//                    .foregroundStyle(foregroundStyle)
//                    .padding(8)
//                    .background(background)
//                    .clipShape(Circle())
//                    .animation(.easeInOut(duration: 0.2), value: selectedDay)
//                    .onTapGesture {
//                        selectedDay = date
//                    }
//            }
//        }
//    }
//}
//
//enum DisplayMode: String, CaseIterable, Identifiable {
//    case day, week
//    var id: Self {
//        self
//    }
//}
//
//struct ScheduleViewTitle: View {
//    @Binding var displayMode: DisplayMode
//    @Binding var selectedDay: Date
//
//    var body: some View {
//        HStack {
//            Text(selectedDay.localeMonth())
//                .font(.largeTitle.bold())
//
//            Spacer()
//
//            HStack(spacing: 20) {
//                Menu {
//                    Picker(selection: $displayMode, label: Text("")) {
//                        Label("单日", systemImage: "calendar.day.timeline.left").tag(DisplayMode.day)
//                        Label("一周", systemImage: "calendar").tag(DisplayMode.week)
//                    }
//                } label: {
//                    Image(systemName: displayMode == .day ? "calendar.day.timeline.left" : "calendar")
//                        .font(.title2)
//                }
//
//                Button(action: {
//
//                }) {
//                    Image(systemName: "plus")
//                        .font(.title2)
//                }
//            }
//        }
//    }
//}
//
//struct WeekTabView: View {
//    @Binding var selectedDay: Date
//    let baseDay: Date
//    @State private var scrollPosition: ScrollPosition = .init(id: 0)
//    @State private var data = Array(-5...5)
//
//    var body: some View {
//        ScrollView(.horizontal) {
//            LazyHStack {
//                ForEach(data, id: \.self) { offset in
//                    let week = baseDay.addWeek(offset)
//                    GeometryReader { geometry in
//                        WeekView(selectedDay: $selectedDay, week: week)
//                            .frame(width: geometry.size.width)
//                    }
//                    .frame(width: UIScreen.main.bounds.width)
//                }
//            }
//            .scrollTargetLayout()
//        }
//        .scrollTargetBehavior(.viewAligned)
//        .scrollIndicators(.hidden)
//        .scrollPosition($scrollPosition)
//        .onChange(of: selectedDay) {
//            let id = selectedDay.weeksSince(baseDay)
//            let currentOffset = scrollPosition.viewID(type: Int.self)!
//            if id != currentOffset {
//                withAnimation {
//                    scrollPosition.scrollTo(id: id)
//                }
//            }
//        }
//        .onChange(of: scrollPosition) {
//            let weekOffset = scrollPosition.viewID(type: Int.self)!
//            if weekOffset != selectedDay.weeksSince(baseDay) {
//                selectedDay = selectedDay.addingTimeInterval(TimeInterval(7 * 60 * 60 * 24 * (weekOffset - selectedDay.weeksSince(baseDay))))
//            }
//        }
//        .onScrollPhaseChange { oldPhase, newPhase, context in
//            if oldPhase == .decelerating && newPhase == .idle {
//                let weekOffset = scrollPosition.viewID(type: Int.self)!
//                data = Array(weekOffset - 5...weekOffset + 5)
//            }
//        }
//        .frame(height: 40)
//    }
//
//    //    var body: some View {
//    //        InfinitePageView(
//    //            selection: $weekOffset,
//    //            before: { $0 - 1 },
//    //            after: { $0 + 1 },
//    //            view: { offset in
//    //                let week = baseDay.addingTimeInterval(TimeInterval(7 * 60 * 60 * 24 * offset))
//    //                WeekView(selectedDay: $selectedDay, week: week)
//    //            }
//    //        )
//    //        .onChange(of: weekOffset) {
//    //            selectedDay = selectedDay.addingTimeInterval(TimeInterval(7 * 60 * 60 * 24 * (weekOffset - previousWeekOffset)))
//    //            previousWeekOffset = weekOffset
//    //        }
//    //        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
//    //        .frame(height: 40)
//    //    }
//}
//
//struct DayTabView: View {
//    @Binding var selectedDay: Date
//    let baseDay: Date
//    @State private var scrollPosition: ScrollPosition = .init(id: 0)
//    @State private var data = Array(-5...5)
//    @State private var previousDay: Date?
//
//    var body: some View {
//        ScrollView(.horizontal) {
//            LazyHStack {
//                ForEach(data, id: \.self) { offset in
//                    let day = baseDay.addingTimeInterval(TimeInterval(60 * 60 * 24 * offset))
//                    GeometryReader { geometry in
//                        ScrollView {
//                            Text(day.formatted())
//                                .padding()
//                        }
//                        .frame(width: geometry.size.width)
//                    }
//                    .frame(width: UIScreen.main.bounds.width)
//                }
//            }
//            .scrollTargetLayout()
//        }
//        .scrollTargetBehavior(.viewAligned)
//        .scrollIndicators(.hidden)
//        .scrollPosition($scrollPosition)
//        .onChange(of: scrollPosition, {
//            let day = baseDay.addingTimeInterval(TimeInterval(60 * 60 * 24 * scrollPosition.viewID(type: Int.self)!))
//            if !selectedDay.isSameDay(as: day) {
//                selectedDay = day
//            }
//        })
//        .onChange(of: selectedDay) {
//            let id = selectedDay.daysSince(baseDay)
//            let daysDiff = previousDay != nil ? selectedDay.daysSince(previousDay!) : 0
//            let currentViewID = scrollPosition.viewID(type: Int.self)!
//            previousDay = selectedDay
//
//            if currentViewID != id {
//                if daysDiff > 0 {
//                    if currentViewID == data.last {
//                        data.append(selectedDay.daysSince(baseDay))
//                    } else {
//                        data[data.firstIndex(of: currentViewID)! + 1] = selectedDay.daysSince(baseDay)
//                    }
//                } else if daysDiff < 0 {
//                    if currentViewID == data.first {
//                        data.insert(selectedDay.daysSince(baseDay), at: 0)
//                    } else {
//                        data[data.firstIndex(of: currentViewID)! - 1] = selectedDay.daysSince(baseDay)
//                    }
//                }
//
//                print(data)
//                print("Scrolling to", id)
//                withAnimation {
//                    scrollPosition.scrollTo(id: id)
//                }
//            }
//        }
//        .onScrollPhaseChange { oldPhase, newPhase, context in
//            if oldPhase == .decelerating && newPhase == .idle {
//                let dayOffset = scrollPosition.viewID(type: Int.self)!
//                data = Array(dayOffset - 5...dayOffset + 5)
//                print(data)
//            } else if oldPhase == .animating && newPhase == .idle {
//                let dayOffset = scrollPosition.viewID(type: Int.self)!
//                data = Array(dayOffset - 5...dayOffset + 5)
//                print("Animation finished", dayOffset, data)
//            }
//        }
//    }
//}
//
//struct ScheduleView: View {
//    @State private var selectedDay: Date = .now
//    @State private var baseDay: Date = .now
//    @State private var lastHostingView: UIView!
//    @State private var displayMode: DisplayMode = .day
//
//    var body: some View {
//        NavigationStack {
//            VStack(spacing: 0) {
//                VStack {
//                    ScheduleViewTitle(displayMode: $displayMode, selectedDay: $selectedDay)
//                        .padding()
//
//                    HStack(spacing: 0) {
//                        let weekdays = Array("一二三四五六日".enumerated())
//                        ForEach(weekdays, id: \.offset) { c in
//                            Text(String(c.element))
//                                .frame(maxWidth: .infinity)
//                                .font(.caption2)
//                        }
//                    }
//
//                    WeekTabView(selectedDay: $selectedDay, baseDay: baseDay)
//                        .padding(.bottom, 6)
//                }
//                .background(Color(UIColor.systemGray6))
//
//                Divider().frame(height: 1).background(Color(UIColor.systemGray6))
//                Text("2024 学年秋季学期・第 9 周 \(selectedDay.localeWeekday())")
//                    .font(.callout)
//                    .fontWeight(.medium)
//                    .padding(EdgeInsets.init(top: 6, leading: 0, bottom: 6, trailing: 0))
//                    .animation(.easeInOut(duration: 0.2), value: selectedDay)
//                Divider().frame(height: 1).background(Color(UIColor.systemGray6))
//
//                DayTabView(selectedDay: $selectedDay, baseDay: baseDay)
//            }
//        }
//    }
//}
//
//#Preview {
//    ScheduleView()
//}
