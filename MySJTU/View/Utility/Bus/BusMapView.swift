//
//  BusMapView.swift
//  MySJTU
//
//  Created by 何炳昌 on 2024/12/18.
//

import SwiftUI
import MapKit
import Alamofire

struct BusResponse<T: Decodable>: Decodable {
    let success: Bool
    let message: String
    let data: [T]
    let code: Int
}

struct BusLine: Decodable, Equatable {
    let id, lineSystemID: Int
    let lineCode, name: String
    let direction: Int
    let startStation, endStation, startTime, endTime: String
    let loop: Bool
    let nameEn, startStationEn, endStationEn: String

    enum CodingKeys: String, CodingKey {
        case id
        case lineSystemID = "line_system_id"
        case lineCode = "line_code"
        case name, direction
        case startStation = "start_station"
        case endStation = "end_station"
        case startTime = "start_time"
        case endTime = "end_time"
        case loop
        case nameEn = "name_en"
        case startStationEn = "start_station_en"
        case endStationEn = "end_station_en"
    }
}

private struct BusRoute: Decodable {
    private let id: Int
    private let lineId: Int
    private let route: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case lineId = "line_id"
        case route
    }
}

extension BusRoute {
    var coordinates: [CLLocationCoordinate2D] {
        route.split(separator: ",").map {
            let points: [Double] = $0.split(separator: " ").map { n in Double(String(n))! }
            return .init(latitude: points[1], longitude: points[0])
        }
    }
}

struct BusStation: Codable, Equatable {
    let id, lineID: Int
    let stationCode: String
    let station: Station
    let index, time: Int

    enum CodingKeys: String, CodingKey {
        case id
        case lineID = "line_id"
        case stationCode = "station_code"
        case station, index, time
    }
}

struct Station: Codable, Equatable {
    let id: Int
    let stationCode, name: String
    let location: Location
    let time: Int
    let nameEn: String

    enum CodingKeys: String, CodingKey {
        case id
        case stationCode = "station_code"
        case name, location
        case time = "Time"
        case nameEn = "name_en"
    }
}

struct Location: Codable, Equatable {
    let latitude, longitude: Double
}

extension Location {
    func coordinate() -> CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}

struct BusSchedule: Codable, Equatable {
    let time: String
    let timeInt: Int
    let executionDate: String
    var type: String

    enum CodingKeys: String, CodingKey {
        case time
        case timeInt = "time_int"
        case executionDate = "execution_date"
        case type
    }
}

struct RealtimeXML: Codable {
    let xml: String
}

struct Car {
    var lineID: String
    var terminal: String
    var stopDistance: Int
    var distance: Int
    var time: Int
    var location: String
    var gpsTime: Int
    var direction: Double
    var inOut: Int
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        return path
    }
}

struct BorderedCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding([.leading, .trailing], 12)
            .padding([.top, .bottom], 7)
            .background(Color(UIColor.systemBackground))
            .foregroundColor(Color(UIColor.label))
            .overlay(Capsule().stroke(Color.gray, lineWidth: 0.5))
    }
}

class MonitorSocket: ObservableObject {
    @Published var vehicles = [VehicleStatus]()
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let decoder = JSONDecoder()

    struct VehicleStatus: Codable, Equatable {
        let location: Location
        let angle: Int
        let vehicleCode, remark: String
        let speed: Int
        let station: String
        let direction, updatedAt, inStation: Int

        enum CodingKeys: String, CodingKey {
            case location, angle
            case vehicleCode = "vehicle_code"
            case remark, speed, station, direction
            case updatedAt = "updated_at"
            case inStation = "in_station"
        }
    }
    
    func connect(lineCode: String, direction: Int) {
        vehicles = []
        webSocketTask?.cancel()
        guard let url = URL(string: "wss://campuslife.sjtu.edu.cn/ws/v1/shuttle/\(lineCode)/\(direction)/monitor/ws") else { return }
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print(error.localizedDescription)
            case .success(let message):
                switch message {
                case .string(let text):
                    do {
                        if let vehicles = try self?.decoder.decode([VehicleStatus].self, from: Data(text.utf8)) {
                            DispatchQueue.main.async{
                                self?.vehicles = vehicles
                            }
                        }
                    } catch {
                        print(error)
                    }
                    self?.receiveMessage()
                case .data(_):
                    break
                @unknown default:
                    break
                }
            }
        }
    }
}

struct BusMapSheet: View {
    fileprivate let stations: [BusStation]
    fileprivate var selectedLine: BusLine?
    @Binding fileprivate var selection: Int?
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    
    @State private var showAllStations = false
    @State private var stationSchedules: [BusSchedule]?
    @State private var activeSchedule: BusSchedule?
    @State private var toMetroStation: Bool = false
    @State private var terminalScrollPosition = ScrollPosition(idType: Int.self)
    @State private var containerScrollPosition = ScrollPosition()
    @State private var scheduleScrollPosition = ScrollPosition(idType: String.self)
    @State private var arrivingBus: Car?
    
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    private var filteredSchedules: [BusSchedule]? {
        stationSchedules?.filter { toMetroStation ? $0.type == "normal/in" : true }
    }
    
    private var comingSchedules: [BusSchedule] {
        var _schedules: [BusSchedule] = []
        
        if let schedules = filteredSchedules {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current
            
            for schedule in schedules {
                let time = formatter.date(from: schedule.time)!
                if let arrivingBus {
                    if !time.timeIsBefore(.now) {
                        _schedules.append(schedule)
                    } else {
                        let arrivingTime = Date.now.addSeconds(arrivingBus.time)
                        if abs(arrivingTime.secondsFromTime(time)) <= 300 {
                            _schedules.append(schedule)
                        }
                    }
                } else {
                    if !time.timeIsBefore(.now) {
                        _schedules.append(schedule)
                    }
                }
            }
        }
        
        return _schedules
    }
    
    private func updateRealtime() {
        if let filteredSchedules, filteredSchedules.count > 0, let selection, let selectedLine, let station = stations.first(where: { $0.id == selection }) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

            Task {
                do {
                    let response = try await AF.request(
                        "http://wx.shmhky.com:8188/minhang/weixin/carMonitor.do",
                        parameters: [
                            "lineid": selectedLine.lineSystemID,
                            "direction": selectedLine.direction,
                            "stopid": station.stationCode.split(separator: "-").first!
                        ],
                        encoding: URLEncoding(destination: .queryString)
                    )
                        .serializingDecodable(RealtimeXML.self)
                        .value
                    
                    let parser = XMLCarParser()

                    if let cars = parser.parse(data: Data(response.xml.utf8)) {
                        arrivingBus = cars.first
                    }
                } catch {
                    print(error)
                }
            }
        }
    }
    
    var body: some View {
        var formatter: DateFormatter {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
            return f
        }
        
        if let selectedLine {
            var stations: [BusStation] {
                if let activeSchedule, self.stations.count > 0 {
                    if activeSchedule.type == "normal" {
                        return self.stations.filter { $0.stationCode != "FFFF43" }
                    } else if activeSchedule.type == "out/normal" {
                        return Array(self.stations[0..<self.stations.count - 1])
                    } else if activeSchedule.type == "normal/in" {
                        return Array(self.stations[1..<self.stations.count])
                    } else {
                        return self.stations
                    }
                } else {
                    if toMetroStation {
                        return Array(self.stations[1..<self.stations.count])
                    } else if selectedLine.direction == 1, self.stations.first(where: { $0.id == selection })?.stationCode == "FFFF43" {
                        return Array(self.stations[0..<self.stations.count - 1])
                    } else {
                        return self.stations.filter { $0.stationCode != "FFFF43" }
                    }
                }
            }
            
            ScrollView {
                VStack(spacing: 0) {
                    if selectedLine.lineCode == "918484" {
                        ScrollView(.horizontal) {
                            HStack {
                                Button("菁菁堂广场") {
                                    toMetroStation = false
                                    terminalScrollPosition.scrollTo(id: 0)
                                }
                                .font(.callout)
                                .if(toMetroStation) {
                                    $0.buttonStyle(BorderedCapsuleButtonStyle())
                                }
                                .if(!toMetroStation) {
                                    $0.buttonStyle(.borderedProminent)
                                }
                                .clipShape(.capsule)
                                .tint(.blue)
                                .id(0)
                                
                                if stations.first(where: { $0.id == selection })?.stationCode != "FFFF43" {
                                    Button("菁菁堂广场经由，开往东川路地铁站") {
                                        toMetroStation = true
                                        withAnimation {
                                            terminalScrollPosition.scrollTo(id: 1)
                                        }
                                    }
                                    .font(.callout)
                                    .if(toMetroStation) {
                                        $0.buttonStyle(.borderedProminent)
                                    }
                                    .if(!toMetroStation) {
                                        $0.buttonStyle(BorderedCapsuleButtonStyle())
                                    }
                                    .clipShape(.capsule)
                                    .tint(.blue)
                                    .id(1)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollPosition($terminalScrollPosition)
                        .padding([.bottom])
                        .contentMargins([.leading, .trailing], 14, for: .scrollContent)
                    }
                    
                    if selection != nil {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("临近出发班次")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding([.leading, .trailing])
                            
                            if stationSchedules != nil, comingSchedules.count > 0 {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(zip(comingSchedules.indices, comingSchedules)), id: \.1.time) { index, schedule in
                                            VStack {
                                                Button {
                                                    activeSchedule = schedule
                                                    scheduleScrollPosition.scrollTo(id: schedule.time)
                                                } label: {
                                                    VStack(spacing: 0) {
                                                        let time = formatter.date(from: schedule.time)!
                                                        
                                                        if index == 0, let arrivingBus, abs(Date.now.addSeconds(arrivingBus.time).secondsFromTime(time)) <= 300 {
                                                            let arrivingTime = Date.now.addSeconds(arrivingBus.time)
                                                            let diff = arrivingTime.secondsFromTime(time)
                                                            
                                                            HStack(spacing: 2) {
                                                                Text(schedule.time)
                                                                    .fontWeight(
                                                                        schedule.time == activeSchedule?.time ?
                                                                            .semibold : .medium
                                                                    )
                                                                    .foregroundStyle(
                                                                        schedule.time == activeSchedule?.time ? Color(UIColor.label) : Color(UIColor.secondaryLabel)
                                                                    )
                                                                
                                                                Image(systemName: "dot.radiowaves.up.forward")
                                                                    .resizable()
                                                                    .scaledToFit()
                                                                    .frame(width: 12, height: 12)
                                                                    .foregroundStyle(
                                                                        schedule.time == activeSchedule?.time ? (diff <= 0 ? Color.green : Color.red) : Color(UIColor.secondaryLabel)
                                                                    )
                                                            }
                                                            
                                                            Text(diff <= 0 ? "准时" : "最新 \(formatter.string(from: arrivingTime))")
                                                                .font(.caption)
                                                                .foregroundStyle(
                                                                    schedule.time == activeSchedule?.time ? (diff <= 0 ? Color.green : Color.red) : Color(UIColor.tertiaryLabel)
                                                                )
                                                        } else {
                                                            Text(schedule.time)
                                                                .fontWeight(
                                                                    schedule.time == activeSchedule?.time ?
                                                                        .semibold : .medium
                                                                )
                                                                .foregroundStyle(
                                                                    schedule.time == activeSchedule?.time ? Color(UIColor.label) : Color(UIColor.secondaryLabel)
                                                                )
                                                            
                                                            Text("计划")
                                                                .font(.caption)
                                                                .foregroundStyle(
                                                                    schedule.time == activeSchedule?.time ? Color(UIColor.secondaryLabel) : Color(UIColor.tertiaryLabel)
                                                                )
                                                        }
                                                    }
                                                    .padding([.leading, .trailing])
                                                    .padding([.top, .bottom], 8)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .background(
                                                schedule.time == activeSchedule?.time ? Color(UIColor.secondarySystemGroupedBackground) : Color(UIColor.tertiarySystemGroupedBackground)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .if(schedule.time == activeSchedule?.time && colorScheme == .light) {
                                                $0.shadow(color: Color(UIColor.systemGray3), radius: 1, x: 0, y: 1)
                                            }
                                            .padding([.top], 8)
                                            .padding([.bottom])
                                            .id(schedule.time)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .scrollIndicators(.hidden)
                                .scrollPosition($scheduleScrollPosition)
                                .contentMargins([.leading, .trailing], 14, for: .scrollContent)
                            } else if stationSchedules != nil, comingSchedules.count == 0 {
                                VStack {
                                    Text("今日运营已结束")
                                        .padding()
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding([.leading, .trailing, .bottom])
                                .padding([.top], 8)
                            } else {
                                VStack {
                                    ProgressView().padding()
                                }
                                .frame(maxWidth: .infinity)
                                .padding([.leading, .trailing, .bottom])
                            }
                        }
                        .frame(height: 96, alignment: .top)
                        .animation(.easeInOut, value: stationSchedules)
                        .animation(.easeInOut, value: comingSchedules)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("停靠站")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                            Button {
                                showAllStations.toggle()
                            } label: {
                                showAllStations ? Text("收起") : Text("更多")
                            }
                            .tint(.blue)
                        }
                        
                        VStack(spacing: 0) {
                            if stations.count > 0 {
                                var startIndex: Int {
                                    if let selection, let selectStation = stations.firstIndex(where: { $0.id == selection }) {
                                        return selectStation
                                    } else {
                                        return 0
                                    }
                                }
                                
                                if !showAllStations && startIndex - 1 > 0 {
                                    HStack(spacing: 0) {
                                        // dot and line
                                        ZStack {
                                            Line()
                                                .stroke(style: StrokeStyle(lineWidth: 4, dash: [5]))
                                                .fill(Color(UIColor.systemGray2))
                                                .frame(width: 4)
                                                .offset(x: 2)
                                        }
                                        .frame(width: 36, height: 24)
                                        
                                        // station name
                                        Text("前\(startIndex - 1)站")
                                            .foregroundStyle(Color(UIColor.systemGray2))
                                        
                                        Spacer()
                                        // time
                                    }
                                    .padding([.leading, .trailing])
                                }
                                
                                let lowerBound = showAllStations ? 0 : max(0, startIndex - 1)
                                ForEach(Array(stations[lowerBound..<stations.count]), id: \.id) { station in
                                    let index = stations.firstIndex { $0.id == station.id }!
                                    
                                    if index < startIndex {
                                        HStack(spacing: 0) {
                                            // dot and line
                                            ZStack(alignment: .center) {
                                                if index != 0 {
                                                    Rectangle()
                                                        .fill(Color(UIColor.systemGray2))
                                                        .frame(width: 4, height: 24)
                                                        .position(x: 18, y: 12)
                                                }
                                                
                                                Rectangle()
                                                    .fill(Color(UIColor.systemGray2))
                                                    .frame(width: 4, height: 24)
                                                    .position(x: 18, y: 36)
                                                
                                                if index == 0{
                                                    Circle()
                                                        .fill(Color(UIColor.systemGray2))
                                                        .stroke(Color(UIColor.systemBackground), lineWidth: 0.5)
                                                        .frame(width: 12, height: 12)
                                                        .position(x: 18, y: 24)
                                                } else {
                                                    Circle()
                                                        .fill(Color(UIColor.systemBackground))
                                                        .stroke(Color(UIColor.systemGray2), lineWidth: 2)
                                                        .frame(width: 8, height: 8)
                                                        .position(x: 18, y: 24)
                                                }
                                            }
                                            .frame(width: 36, height: 48)
                                            
                                            // station name
                                            Button {
                                                if station.id != stations.last?.id {
                                                    selection = station.id
                                                }
                                            } label: {
                                                Text(station.station.name)
                                                    .fontWeight(station.id == selection ? .semibold : .regular)
                                                    .foregroundStyle(Color(UIColor.systemGray2))
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Spacer()
                                            // time
                                        }
                                        .padding([.leading, .trailing])
                                    } else {
                                        HStack(spacing: 0) {
                                            // dot and line
                                            ZStack(alignment: .center) {
                                                if index != 0 {
                                                    Rectangle()
                                                        .fill(startIndex == index ? Color(UIColor.systemGray2) : Color.blue)
                                                        .frame(width: 4, height: 24)
                                                        .position(x: 18, y: 12)
                                                }
                                                
                                                if index != stations.count - 1 {
                                                    Rectangle()
                                                        .fill(Color.blue)
                                                        .frame(width: 4, height: 24)
                                                        .position(x: 18, y: 36)
                                                }
                                                
                                                if station.id == selection {
                                                    Circle()
                                                        .fill(Color(UIColor.systemBackground))
                                                        .stroke(Color.blue, lineWidth: 4)
                                                        .frame(width: 12, height: 12)
                                                        .position(x: 18, y: 24)
                                                } else if index == 0 || index == stations.count - 1 {
                                                    Circle()
                                                        .fill(Color.blue)
                                                        .stroke(Color(UIColor.systemBackground), lineWidth: 0.5)
                                                        .frame(width: 12, height: 12)
                                                        .position(x: 18, y: 24)
                                                } else {
                                                    Circle()
                                                        .fill(Color(UIColor.systemBackground))
                                                        .stroke(Color.blue, lineWidth: 2)
                                                        .frame(width: 8, height: 8)
                                                        .position(x: 18, y: 24)
                                                }
                                            }
                                            .frame(width: 36, height: 48)
                                            
                                            // station name
                                            Button {
                                                if station.id != stations.last?.id {
                                                    selection = station.id
                                                }
                                            } label: {
                                                Text(station.station.name)
                                                    .fontWeight(station.id == selection ? .semibold : .regular)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Spacer()
                                            // time
                                            if let activeSchedule, let selection {
                                                var time: String {
                                                    if let stationIndex = stations.firstIndex(where: { $0.id == selection }) {
                                                        var scheduleTime = formatter.date(from: activeSchedule.time)!
                                                        
                                                        for i in 0...stationIndex {
                                                            let time = (i == 1 && stations[0].stationCode == "FFFF43") ? 10 : stations[i].time
                                                            scheduleTime = scheduleTime.addMinutes(-time)
                                                        }
                                                        
                                                        for i in 0...index {
                                                            let time = (i == 1 && stations[0].stationCode == "FFFF43") ? 10 : stations[i].time
                                                            scheduleTime = scheduleTime.addMinutes(time)
                                                        }
                                                        
                                                        if index == stations.count - 1 && stations[index].stationCode == "FFFF43" {
                                                            scheduleTime = scheduleTime.addMinutes(10)
                                                        }
                                                        
                                                        return formatter.string(from: scheduleTime)
                                                    }
                                                    return ""
                                                }
                                                
                                                Text(time)
                                                    .font(.callout)
                                            }
                                        }
                                        .padding([.leading, .trailing])
                                    }
                                }
                            } else {
                                ProgressView()
                                    .padding()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .animation(.easeInOut, value: showAllStations)
                    }
                    .animation(.easeInOut, value: selection)
                    .animation(.easeInOut, value: stations)
                    .padding([.leading, .trailing])
                }
            }
            .scrollPosition($containerScrollPosition)
            .onReceive(timer) { input in
                updateRealtime()
            }
            .onChange(of: comingSchedules) {
                if comingSchedules.first(where: { $0.time == activeSchedule?.time }) == nil {
                    activeSchedule = comingSchedules.first
                }
            }
            .onChange(of: selection) {
                Task {
                    if !showAllStations {
                        withAnimation {
                            containerScrollPosition.scrollTo(edge: .top)
                        }
                    }
                    
                    if self.stations.first(where: { $0.id == selection })?.stationCode == "FFFF43" {
                        toMetroStation = false
                    }
                    
                    if let station = self.stations.first(where: { $0.id == selection }) {
                        stationSchedules = nil
                        arrivingBus = nil
                        
                        if station.id != stations.last?.id {
                            do {
                                let schedules = try await AF.request("https://campuslife.sjtu.edu.cn/api/v1/shuttle/\(selectedLine.lineSystemID)/\(selectedLine.direction)/timetable/\(station.id)")
                                    .serializingDecodable(BusResponse<BusSchedule>.self)
                                    .value
                                    .data
                                    .filter { schedule in
                                        !(schedule.timeInt > 1200 && schedule.type == "out")
                                    }
                                
                                arrivingBus = nil
                                self.stationSchedules = schedules
                                updateRealtime()
                            } catch {
                                print(error)
                            }
                        } else {
                            selection = nil
                        }
                    }
                }
            }
        }
    }
}

class XMLCarParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentCar: Car?
    private var cars: [Car] = []
    private var currentValue: String = ""
    
    func parse(data: Data) -> [Car]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if parser.parse() {
            return cars
        } else {
            return nil
        }
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "cars" {
            if let lineID = attributeDict["lineid"] {
                currentCar = Car(lineID: lineID, terminal: "", stopDistance: 0, distance: 0, time: 0, location: "", gpsTime: 0, direction: 0.0, inOut: 0)
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "terminal":
            currentCar?.terminal = currentValue
        case "stopdis":
            currentCar?.stopDistance = Int(currentValue) ?? 0
        case "distance":
            currentCar?.distance = Int(currentValue) ?? 0
        case "time":
            currentCar?.time = Int(currentValue) ?? 0
        case "loc":
            currentCar?.location = currentValue
        case "gpstime":
            currentCar?.gpsTime = Int(currentValue) ?? 0
        case "direction":
            currentCar?.direction = Double(currentValue) ?? 0.0
        case "inout":
            currentCar?.inOut = Int(currentValue) ?? 0
        case "car":
            if let currentCar {
                cars.append(currentCar)
            }
            currentCar = nil
        default:
            break
        }
        currentValue = ""
    }
}

struct BusMapView: View {
    var selectedLine: BusLine
    @State private var route: BusRoute?
    @State private var stations: [BusStation] = []
    @State private var position: MapCameraPosition = .camera(
        .init(centerCoordinate: .init(latitude: 31.02223853775149, longitude: 121.4367061348467), distance: 9963.584473701083)
    )
    @State private var selection: Int?
    @State private var sheetDetent: PresentationDetent = .fraction(0.2)
    @State private var showSheet: Bool = true
    @StateObject private var websocket = MonitorSocket()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            Map(position: $position, selection: $selection) {
                //            ForEach(stations, id: \.id) { station in
                //                Annotation(station.station.name, coordinate: station.station.location.coordinate(), anchor: .center) {
                //                    let isSelected = (selection == station.id)
                //                    ZStack(alignment: .center) {
                //                        if isSelected {
                //                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                //                                .fill(Color(UIColor.tintColor))
                //                                .frame(width: 64, height: 64)
                //                                .overlay {
                //                                    Image(systemName: "checkmark")
                //                                        .foregroundStyle(.white)
                //                                        .frame(width: 48, height: 48)
                //                                }
                //                        } else {
                //                            Circle()
                //                                .stroke(Color(UIColor.tintColor), lineWidth: 3)
                //                                .fill(.white)
                //                                .frame(width: 7, height: 7)
                //                        }
                //                    }
                //                    .animation(.easeInOut, value: isSelected)
                //                }
                //                .tag(station.id)
                //            }
                
                var filteredStations: [BusStation] {
                    if selectedLine.lineCode == "918484", stations.count > 1, selectedLine.direction == 0 {
                        return Array(stations[1..<stations.count])
                    } else {
                        return stations
                    }
                }
                ForEach(filteredStations, id: \.id) { station in
                    Marker(station.station.name, systemImage: "\(selectedLine.lineCode == "918484" ? station.index - 1 : station.index).circle.fill", coordinate: station.station.location.coordinate())
                        .tint(.blue)
                        .tag(station.id)
                }
                
                if let route {
                    MapPolyline(coordinates: route.coordinates, contourStyle: .geodesic)
                        .stroke(.blue, lineWidth: 4)
                }
                                
                ForEach(websocket.vehicles.filter { Date.now.secondsFromTime(Date(timeIntervalSince1970: Double($0.updatedAt) / 1000)) <= 300 }, id: \.vehicleCode) { vehicle in
                    Annotation(coordinate: vehicle.location.coordinate()) {
                        Circle()
                            .stroke(.white, lineWidth: 6)
                            .fill(Color.blue)
                            .frame(width: 22, height: 22)
                            .shadow(radius: 6)
                            .overlay {
                                Image(systemName: "bus")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(Color.white)
                                    .frame(width: 14, height: 14)
                            }
                    } label: {
                        Text(vehicle.vehicleCode)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            //            .safeAreaInset(edge: .bottom) {
            //                var height: CGFloat {
            //                    switch sheetDetent {
            //                    case .height(200):
            //                        return 200
            //                    case .height(400):
            //                        return 400
            //                    case .height(600):
            //                        return 600
            //                    default:
            //                        return 0
            //                    }
            //                }
            //
            //                EmptyView()
            //                    .frame(height: max(height - geometry.safeAreaInsets.bottom + 24, 0))
            //            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            // .navigationTitle("校园巴士")
            .animation(.easeInOut, value: websocket.vehicles)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSheet = false
                        dismiss()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSheet) {
                NavigationStack {
                    BusMapSheet(
                        stations: stations,
                        selectedLine: selectedLine,
                        selection: $selection
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            VStack(alignment: .center, spacing: 3) {
                                let startStation = stations.first?.station.name ?? ""
                                let endStation = stations.last?.station.name ?? ""
                                
                                Text(selectedLine.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                if stations.first == nil {
                                    Text(" ")
                                        .font(.callout)
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                } else if startStation == endStation {
                                    Text(selectedLine.direction == 0 ? "顺时针" : "逆时针")
                                        .font(.callout)
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                } else {
                                    Text("开往 \(endStation)")
                                        .font(.callout)
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .interactiveDismissDisabled()
                .presentationBackgroundInteraction(.enabled)
                .presentationDetents([.fraction(0.2), .fraction(0.5), .large], selection: $sheetDetent)
                .presentationDragIndicator(.visible)
                // .presentationBackground(.ultraThickMaterial)
                // .ignoresSafeArea()
                .animation(.easeInOut, value: selectedLine)
                .animation(.easeInOut, value: stations)
            }
            .task {
                do {
                    websocket.connect(lineCode: selectedLine.lineCode, direction: selectedLine.direction)
                    
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            do {
                                let route = try await AF.request("https://campuslife.sjtu.edu.cn/api/v1/shuttle/\(selectedLine.lineCode)/\(selectedLine.direction)/route")
                                    .serializingDecodable(BusResponse<BusRoute>.self)
                                    .value
                                    .data
                                    .first
                                Task { @MainActor in
                                    self.route = route
                                }
                            } catch {
                                print(error)
                            }
                        }
                        
                        group.addTask {
                            do {
                                let stations = try await AF.request("https://campuslife.sjtu.edu.cn/api/v1/shuttle/\(selectedLine.lineCode)/\(selectedLine.direction)/stations")
                                    .serializingDecodable(BusResponse<BusStation>.self)
                                    .value
                                    .data
                                Task { @MainActor in
                                    self.stations = stations
                                }
                            } catch {
                                print(error)
                            }
                        }
                    }
                } catch {
                    print(error)
                }
            }
            .task {
                if selectedLine.lineCode != "918484" {
                    position = .camera(
                        .init(centerCoordinate: .init(latitude: 31.033039, longitude: 121.442041), distance: 9963.584473701083)
                    )
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
            .onChange(of: selection) {
                if let station = stations.first(where: { $0.id == selection }) {
                    withAnimation {
                        position = .camera(
                            .init(centerCoordinate: station.station.location.coordinate(), distance: 3600)
                        )
                    }
                }
            }
        }
    }
}
