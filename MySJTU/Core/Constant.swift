//
//  Constant.swift
//  MySJTU
//
//  Created by boar on 2024/11/06.
//

struct Period: Identifiable {
    let id: Int
    let start: String
    let finish: String
    let description: String?

    init(id: Int, start: String, finish: String, description: String? = nil) {
        self.id = id
        self.start = start
        self.finish = finish
        self.description = description
    }
}

typealias TimeTable = Array<Period>

extension TimeTable {
    func getHours() -> (Int, Int) {
        if self.count == 0 {
            return (0, 0)
        }
        let start = Int(self.first!.start.split(separator: ":").first!)!
        var finish = Int(self.last!.finish.split(separator: ":").first!)!
        let finishMinute = Int(self.last!.finish.split(separator: ":").last!)!
        if finishMinute > 0 {
            finish += 1
        }

        return (start, finish)
    }
}

let CollegeTimeTable: Dictionary<College, TimeTable> = [
    College.sjtu: [
        Period(id: 0, start: "8:00", finish: "8:45"),
        Period(id: 1, start: "8:55", finish: "9:40"),
        Period(id: 2, start: "10:00", finish: "10:45"),
        Period(id: 3, start: "10:55", finish: "11:40"),
        Period(id: 4, start: "12:00", finish: "12:45"),
        Period(id: 5, start: "12:55", finish: "13:40"),
        Period(id: 6, start: "14:00", finish: "14:45"),
        Period(id: 7, start: "14:55", finish: "15:40"),
        Period(id: 8, start: "16:00", finish: "16:45"),
        Period(id: 9, start: "16:55", finish: "17:40"),
        Period(id: 10, start: "18:00", finish: "18:45"),
        Period(id: 11, start: "18:55", finish: "19:40"),
        Period(id: 12, start: "20:00", finish: "20:45"),
        Period(id: 13, start: "20:55", finish: "21:30"),
    ],
    College.sjtug: [
        Period(id: 0, start: "8:00", finish: "8:45"),
        Period(id: 1, start: "8:55", finish: "9:40"),
        Period(id: 2, start: "10:00", finish: "10:45"),
        Period(id: 3, start: "10:55", finish: "11:40"),
        Period(id: 4, start: "12:00", finish: "12:45"),
        Period(id: 5, start: "12:55", finish: "13:40"),
        Period(id: 6, start: "14:00", finish: "14:45"),
        Period(id: 7, start: "14:55", finish: "15:40"),
        Period(id: 8, start: "16:00", finish: "16:45"),
        Period(id: 9, start: "16:55", finish: "17:40"),
        Period(id: 10, start: "18:00", finish: "18:45"),
        Period(id: 11, start: "18:55", finish: "19:40"),
        Period(id: 12, start: "19:41", finish: "20:20"),
        Period(id: 13, start: "20:25", finish: "21:10"),
        Period(id: 14, start: "21:15", finish: "22:00"),
    ],
    College.shsmu: [
        Period(id: 0, start: "8:00", finish: "8:40"),
        Period(id: 1, start: "8:50", finish: "9:30"),
        Period(id: 2, start: "9:40", finish: "10:20"),
        Period(id: 3, start: "10:30", finish: "11:10"),
        Period(id: 4, start: "11:20", finish: "12:00"),
        Period(id: -1, start: "12:00", finish: "13:30", description: "午休"),
        Period(id: 5, start: "13:30", finish: "14:10"),
        Period(id: 6, start: "14:20", finish: "15:00"),
        Period(id: 7, start: "15:10", finish: "15:50"),
        Period(id: 8, start: "16:00", finish: "16:40"),
        Period(id: 9, start: "16:50", finish: "17:30"),
        Period(id: 10, start: "17:40", finish: "18:20"),
        Period(id: 11, start: "18:30", finish: "19:10"),
        Period(id: 12, start: "19:20", finish: "20:00"),
        Period(id: 13, start: "20:10", finish: "20:50"),
    ]
]

func getPeriodByTime(college: College, time: String) -> Period? {
    let periods = CollegeTimeTable[college]!
    return periods.first { period in
        Int(period.start.split(separator: ":")[0])! * 100 + Int(period.start.split(separator: ":")[1])! == Int(time.split(separator: ":")[0])! * 100 + Int(time.split(separator: ":")[1])!
    }
}

typealias ClassColorsType = [String]

let ClassColors: ClassColorsType = [
  "#CB1B45",
  "#DB4D6D",
  "#C73E3A",
  "#F75C2F",
  "#1B813E",
  "#2D6D4B",
  "#268785",
  "#336774",
  "#006284",
  "#4E4F97",
  "#005CAF",
  "#66327C",
  "#622954",
  "#C1328E",
];

extension ClassColorsType {
    func randomColors(n: Int = ClassColors.count) -> [String] {
        let shuffled = self.shuffled()
        return Array(shuffled[0..<n])
    }
}
