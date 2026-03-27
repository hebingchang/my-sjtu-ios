//
//  CostAnalytics.swift
//  MySJTU
//
//  Created by boar on 2024/12/24.
//

import SwiftUI
import Charts

private enum AnalyticsMode: Equatable {
    case monthly(year: Int, month: Int)
    case yearly(year: Int)
}

private struct DailyCost: Equatable {
    var day: Range<Date>
    var cost: Double
}

private struct MonthlyCost: Equatable {
    var month: Range<Date>
    var cost: Double
}

private struct HourlyCost: Equatable {
    var hour: Range<Date>
    var cost: Double
    var count: Int
}

private struct MerchantCost: Equatable {
    var merchant: String
    var cost: Double
    var count: Int
}

private struct TypedCost: Equatable {
    var type: CostType
    var cost: Double
    var transactions: [CardTransaction]
}

private enum CostType: String, Equatable {
    case restaurant = "餐饮"
    case shopping = "购物"
    case bathroom = "浴室"
    case charging = "充电"
    case entertainment = "文娱体育"
    case transportation = "交通"
    case other = "其他"
}

private struct AnalyticsMatrics: Equatable {
    var amount: Double?
    var cardAmount: Double?
    var unicodeAmount: Double?
    var dailyCost: [DailyCost]?
    var monthlyCost: [MonthlyCost]?
    var typedCosts: [TypedCost]?
    var hourlyCost: [HourlyCost]?
    var merchantCost: [MerchantCost]?
}

private func transactionsToTypedCost(_ transactions: [CardTransaction]) -> [TypedCost] {
    var types: [CostType: [CardTransaction]] = [
        .bathroom: [],
        .entertainment: [],
        .charging: [],
        .other: [],
        .restaurant: [],
        .shopping: [],
        .transportation: []
    ]
    
    let licenseRegex = /(([京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼使领][A-Z](([0-9]{5}[DF])|([DF]([A-HJ-NP-Z0-9])[0-9]{4})))|([京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼使领][A-Z][A-HJ-NP-Z0-9]{4}[A-HJ-NP-Z0-9挂学警港澳使领]))/

    for transaction in transactions {
        if transaction.merchant.contains("充电") {
            types[.charging]?.append(transaction)
        } else if transaction.merchant.contains("浴") ||
                    transaction.system.contains("水控") ||
                    transaction.merchant.contains("水控") {
            types[.bathroom]?.append(transaction)
        } else if transaction.merchant.contains("教超") {
            types[.shopping]?.append(transaction)
        } else if transaction.merchant.contains("健身") ||
                    transaction.merchant.contains("教材") {
            types[.entertainment]?.append(transaction)
        } else if transaction.merchant.contains(licenseRegex) {
            types[.transportation]?.append(transaction)
        } else if transaction.merchant.contains("面") ||
                    transaction.merchant.contains("烧腊") ||
                    transaction.merchant.contains("点心") ||
                    transaction.merchant.contains("美食") ||
                    transaction.merchant.contains("铁板烧") ||
                    transaction.merchant.contains("牛百碗") ||
                    transaction.merchant.contains("秋林") ||
                    transaction.merchant.contains("麻辣香锅") ||
                    transaction.merchant.contains("餐") ||
                    transaction.system.contains("餐"){
            types[.restaurant]?.append(transaction)
        } else {
            types[.other]?.append(transaction)
        }
    }
            
    var typesArray: [TypedCost] = []
    for type in types.keys {
        if let trans = types[type], trans.count > 0 {
            typesArray.append(.init(type: type, cost: trans.reduce(0) { $0 + $1.amount }, transactions: trans))
        }
    }
    return typesArray
}

struct CostAnalytics: View {
    var campusCard: CampusCard
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @AppStorage("card.enable_unicode") var showUnicode: Bool = false
    @Environment(\.dismiss) var dismiss

    @State private var initialized: Bool = false
    @State private var loading: Bool = false
    @State private var mode: AnalyticsMode?
    @State private var startMonth: DateComponents?
    @State private var latestMonth: DateComponents?
    @State private var noData: Bool = false
    @State private var metrics: AnalyticsMatrics?

    var body: some View {
        let account = accounts.first { $0.provider == .jaccount }
        var isMonthly: Bool {
            switch mode {
            case .monthly(_, _):
                return true
            default:
                return false
            }
        }

        ZStack {
            List {
                if let metrics {
                    if let amount = metrics.amount {
                        VStack {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text("\(isMonthly ? "月" : "年")消费")
                                        .font(.caption)
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                        .fontWeight(.medium)
                                    Text(-amount, format: .currency(code: "CNY"))
                                        .font(.title)
                                        .fontDesign(.rounded)
                                        .fontWeight(.semibold)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 8) {
                                    if let cardAmount = metrics.cardAmount {
                                        VStack(alignment: .trailing) {
                                            Text("校园卡消费")
                                                .font(.caption)
                                                .foregroundStyle(Color(UIColor.secondaryLabel))
                                                .fontWeight(.medium)
                                            Text(-cardAmount, format: .currency(code: "CNY"))
                                                .fontDesign(.rounded)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    
                                    if let unicodeAmount = metrics.unicodeAmount {
                                        VStack(alignment: .trailing) {
                                            Text("思源码消费")
                                                .font(.caption)
                                                .foregroundStyle(Color(UIColor.secondaryLabel))
                                                .fontWeight(.medium)
                                            Text(-unicodeAmount, format: .currency(code: "CNY"))
                                                .fontDesign(.rounded)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                }
                            }
                            
                            if let dailyCost = metrics.dailyCost {
                                Section {
                                    Chart {
                                        ForEach(dailyCost, id: \.day) { daily in
                                            BarMark(
                                                x: .value("日", daily.day),
                                                y: .value("消费", -daily.cost)
                                            )
                                        }
                                    }
                                    .chartYAxis {
                                        AxisMarks(
                                            format: Decimal.FormatStyle.Currency(code: "CNY").precision(.fractionLength(0))
                                        )
                                    }
                                }
                            }
                            
                            if let monthlyCost = metrics.monthlyCost {
                                Section {
                                    Chart {
                                        ForEach(monthlyCost, id: \.month) { monthly in
                                            BarMark(
                                                x: .value("月", monthly.month),
                                                y: .value("消费", -monthly.cost)
                                            )
                                        }
                                    }
                                    .chartYAxis {
                                        AxisMarks(
                                            format: Decimal.FormatStyle.Currency(code: "CNY").precision(.fractionLength(0))
                                        )
                                    }
                                }
                            }
                            
                        }
                        .padding([.top, .bottom])
                    }
                    
                    if let typedCosts = metrics.typedCosts {
                        Section(header: Text("消费类型")) {
                            HStack {
                                Chart {
                                    ForEach(typedCosts, id: \.type) { costs in
                                        SectorMark(
                                            angle: .value("消费", -costs.cost),
                                            innerRadius: .ratio(0.7),
                                            angularInset: 1.5
                                        )
                                        .cornerRadius(5)
                                        .foregroundStyle(by: .value("类型", costs.type.rawValue))
                                    }
                                }
                                .chartLegend(position: .bottom, alignment: .center, spacing: 24)
                                .chartBackground { chartProxy in
                                    GeometryReader { geometry in
                                        if let plotFrame = chartProxy.plotFrame {
                                            let frame = geometry[plotFrame]
                                            if let typedCosts = metrics.typedCosts, let first = typedCosts.first {
                                                VStack {
                                                    Text("最多消费金额")
                                                        .font(.footnote)
                                                        .foregroundStyle(.secondary)
                                                    Text(first.type.rawValue)
                                                        .font(.title2.bold())
                                                        .foregroundColor(.primary)
                                                }
                                                .position(x: frame.midX, y: frame.midY)
                                            }
                                        }
                                    }
                                }
                                .frame(height: 200)
                                
                                Chart {
                                    ForEach(typedCosts, id: \.type) { costs in
                                        SectorMark(
                                            angle: .value("消费次数", costs.transactions.count),
                                            innerRadius: .ratio(0.7),
                                            angularInset: 1.5
                                        )
                                        .cornerRadius(5)
                                        .foregroundStyle(by: .value("类型", costs.type.rawValue))
                                    }
                                }
                                .chartLegend(position: .bottom, alignment: .center, spacing: 24)
                                .chartBackground { chartProxy in
                                    GeometryReader { geometry in
                                        if let plotFrame = chartProxy.plotFrame {
                                            let frame = geometry[plotFrame]
                                            if let typedCosts = metrics.typedCosts, let first = typedCosts.sorted(by: { $0.transactions.count > $1.transactions.count }).first {
                                                VStack {
                                                    Text("最多消费次数")
                                                        .font(.footnote)
                                                        .foregroundStyle(.secondary)
                                                    Text(first.type.rawValue)
                                                        .font(.title2.bold())
                                                        .foregroundColor(.primary)
                                                }
                                                .position(x: frame.midX, y: frame.midY)
                                            }
                                        }
                                    }
                                }
                                .frame(height: 200)
                            }
                            .padding([.top, .bottom])
                        }
                    }
                    
                    if let hourlyCost = metrics.hourlyCost {
                        Section("消费时段") {
                            Chart {
                                ForEach(hourlyCost, id: \.hour) { hourly in
                                    BarMark(
                                        x: .value("时", hourly.hour),
                                        y: .value("消费次数", hourly.count)
                                    )
                                }
                            }
                            .padding([.top, .bottom])
                        }
                    }

                    if let merchantCost = metrics.merchantCost, merchantCost.count > 0 {
                        Section("商家消费次数 TOP 5") {
                            Chart {
                                let sortedCosts = merchantCost.sorted(by: { $0.count > $1.count })[..<min(merchantCost.count, 5)]
                                ForEach(sortedCosts, id: \.merchant) { merchant in
                                    BarMark(
                                        x: .value("消费次数", merchant.count),
                                        y: .value("商家", merchant.merchant),
                                        width: .fixed(8)
                                    )
                                    .annotation(position: .trailing) {
                                        Text(merchant.count.formatted())
                                            .foregroundColor(.secondary)
                                            .font(.caption2)
                                    }
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .chartYAxis {
                                AxisMarks(preset: .extended, position: .leading) { _ in
                                    AxisValueLabel(horizontalSpacing: 15)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            if !initialized {
                ProgressView()
            }
        }
        .animation(.easeInOut, value: initialized)
        .animation(.easeInOut, value: metrics)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let startMonth, let latestMonth, let mode {
                ToolbarItem(placement: .principal) {
                    let currentYear = Date.now.get(.year).year!
                    let currentMonth = Date.now.get(.month).month!
                    let lastMonthYear = Date.now.addMonths(-1).get(.year).year!
                    let lastMonth = Date.now.addMonths(-1).get(.month).month!

                    Menu {
                        Button {
                            self.mode = .monthly(year: currentYear, month: currentMonth)
                        } label: {
                            HStack {
                                Text("本月")
                                Spacer()
                                if mode == .monthly(year: currentYear, month: currentMonth) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Button {
                            self.mode = .monthly(year: lastMonthYear, month: lastMonth)
                        } label: {
                            HStack {
                                Text("上月")
                                Spacer()
                                if mode == .monthly(year: lastMonthYear, month: lastMonth) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Button {
                            self.mode = .yearly(year: currentYear)
                        } label: {
                            HStack {
                                Text("今年")
                                Spacer()
                                if mode == .yearly(year: currentYear) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Section {
                            ForEach((startMonth.year!...latestMonth.year!).reversed(), id: \.self) { year in
                                Menu("\(String(year))年") {
                                    Button {
                                        self.mode = .yearly(year: year)
                                    } label: {
                                        HStack {
                                            Text("全年")
                                            Spacer()
                                            if mode == .yearly(year: year) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                    
                                    Section {
                                        var range: ClosedRange<Int> {
                                            if year == startMonth.year {
                                                return startMonth.month!...12
                                            } else if year == latestMonth.year {
                                                return 1...latestMonth.month!
                                            } else {
                                                return 1...12
                                            }
                                        }
                                        
                                        ForEach(range.reversed(), id: \.self) { month in
                                            Button {
                                                self.mode = .monthly(year: year, month: month)
                                            } label: {
                                                HStack {
                                                    Text("\(month)月")
                                                    Spacer()
                                                    if mode == .monthly(year: year, month: month) {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            switch mode {
                            case .monthly(let year, let month):
                                let yearDescription = year == currentYear ? "" : "\(year)年"
                                if year == currentYear, month == currentMonth {
                                    Text("本月")
                                } else if year == lastMonthYear, month == lastMonth {
                                    Text("上月")
                                } else {
                                    Text("\(yearDescription)\(month)月")
                                }
                            case .yearly(let year):
                                if year == currentYear {
                                    Text("今年")
                                } else if year == currentYear - 1 {
                                    Text("去年")
                                } else {
                                    Text("\(String(year))年")
                                }
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                        }
                        .foregroundStyle(Color(UIColor.label))
                        .fontWeight(.medium)
                    }
                }
            }
        }
        .onChange(of: mode) {
            initialized = false
            metrics = nil
            var beginDate, endDate: Double
            var isMonthly: Bool
            var activeYear = 0
            var activeMonth = 0
            switch mode {
            case .monthly(let year, let month):
                beginDate = Calendar.iso8601.date(from: .init(year: year, month: month))!.timeIntervalSince1970
                endDate = Calendar.iso8601.date(from: .init(year: year, month: month))!.endOfMonth().timeIntervalSince1970
                activeYear = year
                activeMonth = month
                isMonthly = true
            case .yearly(let year):
                beginDate = Calendar.iso8601.date(from: .init(year: year, month: 1, day: 1))!.timeIntervalSince1970
                endDate = Calendar.iso8601.date(from: .init(year: year, month: 12, day: 31))!.endOfMonth().timeIntervalSince1970
                activeYear = year
                isMonthly = false
            case .none:
                return
            }
            
            if let account {
                Task {
                    var metrics = AnalyticsMatrics()
                    
                    do {
                        let api = SJTUOpenAPI(tokens: account.tokens)
                        
                        let (_, cardTransactions) = try await api.getCardTransactions(cardNo: campusCard.cardNo, beginDate: Int(beginDate * 1000), endDate: Int(endDate * 1000))
                        metrics.cardAmount = cardTransactions.reduce(0) { $0 + ($1.amount < 0 ? $1.amount : 0) }
                        
                        var transactions = cardTransactions
                        if showUnicode {
                            let unicodeTransactions = try await api.getUnicodeTransactions(beginDate: Int(beginDate), endDate: Int(endDate))
                            transactions += unicodeTransactions.map { $0.toCardTransaction() }
                            metrics.unicodeAmount = unicodeTransactions.reduce(0) { $0 + ($1.amount < 0 ? $1.amount : 0) }
                        }
                        metrics.amount = (metrics.cardAmount ?? 0) + (metrics.unicodeAmount ?? 0)
                        
                        transactions = transactions.filter { $0.amount < 0 }
                        if isMonthly {
                            var daily: [DailyCost] = []
                            for day in Date(timeIntervalSince1970: beginDate).get(.day).day!...Date(timeIntervalSince1970: endDate).get(.day).day! {
                                let dayRange = Calendar.iso8601.date(from: .init(year: activeYear, month: activeMonth, day: day, hour: 0, minute: 0, second: 0))!..<(Calendar.iso8601.date(from: .init(year: activeYear, month: activeMonth, day: day, hour: 0, minute: 0, second: 0))!.addDays(1).startOfDay())
                                let dailyTransactions = transactions.filter({ Date(timeIntervalSince1970: Double($0.dateTime) / 1000).get(.day).day == day && $0.amount < 0 })
                                daily.append(.init(day: dayRange, cost: dailyTransactions.reduce(0) { $0 + $1.amount }))
                            }
                            metrics.dailyCost = daily
                        } else {
                            var monthly: [MonthlyCost] = []
                            for month in 1...12 {
                                let monthRange = Calendar.iso8601.date(from: .init(year: activeYear, month: month, day: 1, hour: 0, minute: 0, second: 0))!..<(Calendar.iso8601.date(from: .init(year: activeYear, month: month, day: 1, hour: 0, minute: 0, second: 0))!.addMonths(1).startOfMonth())
                                let monthlyTransactions = transactions.filter({ Date(timeIntervalSince1970: Double($0.dateTime) / 1000).get(.month).month == month && $0.amount < 0 })
                                monthly.append(.init(month: monthRange, cost: monthlyTransactions.reduce(0) { $0 + $1.amount }))
                            }
                            metrics.monthlyCost = monthly
                        }
                        
                        var hourlyCost: [HourlyCost] = []
                        for hour in 0...23 {
                            let hourlyTransactions = transactions.filter({ Date(timeIntervalSince1970: Double($0.dateTime) / 1000).get(.hour).hour == hour && $0.amount < 0 })
                            hourlyCost.append(.init(
                                hour: Calendar.iso8601.date(from: .init(hour: hour, minute: 0, second: 0))!..<(Calendar.iso8601.date(from: .init(hour: hour, minute: 0, second: 0))!.addHours(1)),
                                cost: hourlyTransactions.reduce(0) { $0 + $1.amount },
                                count: hourlyTransactions.count
                            ))
                        }
                        metrics.hourlyCost = hourlyCost
                        
                        metrics.merchantCost = Dictionary(grouping: transactions.filter({ $0.amount < 0 }), by: { $0.merchant }).map { (key: String, value: [CardTransaction]) in
                                .init(merchant: key, cost: value.reduce(0) { $0 + $1.amount }, count: value.count)
                        }
                        
                        metrics.typedCosts = transactionsToTypedCost(transactions).sorted { $0.cost < $1.cost }
                    } catch {
                    }
                    
                    self.metrics = metrics
                    initialized = true
                }
            }
        }
        .alert("无法完成消费分析", isPresented: $noData) {
            Button("好", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("目前还没有消费记录")
        }
        .task {
            if let account {
                do {
                    let api = SJTUOpenAPI(tokens: account.tokens)
                    
                    let (_, latestCardTransactions) = try await api.getCardTransactions(cardNo: campusCard.cardNo, limit: 1)
                    let latestUnicodeTransactions = try await api.getUnicodeTransactions(limit: 1)
                    
                    if latestCardTransactions.count == 0 && latestUnicodeTransactions.count == 0 {
                        noData = true
                        return
                    }
                    if let latestCardTransaction = latestCardTransactions.first, let latestUnicodeTransaction = latestUnicodeTransactions.first {
                        let cardDateTime = Date(timeIntervalSince1970: Double(latestCardTransaction.dateTime) / 1000)
                        let unicodeDateTime = Date(timeIntervalSince1970: Double(latestUnicodeTransaction.orderTime))
                        latestMonth = max(cardDateTime, unicodeDateTime).get(.year, .month)
                    } else if let latestCardTransaction = latestCardTransactions.first {
                        let dateTime = Date(timeIntervalSince1970: Double(latestCardTransaction.dateTime) / 1000)
                        latestMonth = dateTime.get(.year, .month)
                    } else if let latestUnicodeTransaction = latestUnicodeTransactions.first {
                        let dateTime = Date(timeIntervalSince1970: Double(latestUnicodeTransaction.orderTime))
                        latestMonth = dateTime.get(.year, .month)
                    }

                    for year in Date.now.get(.year).year!-9...Date.now.get(.year).year! {
                        let startOfYear = Calendar.iso8601.date(from: DateComponents(year: year, month: 1, day: 1))!
                        let endOfYear = Calendar.iso8601.date(from: DateComponents(year: year, month: 12, day: 31, hour: 23, minute: 59, second: 59))!
                        let transactions = try await api.getCardTransactions(cardNo: campusCard.cardNo, beginDate: Int(startOfYear.timeIntervalSince1970) * 1000, endDate: Int(endOfYear.timeIntervalSince1970) * 1000)
                        if transactions.1.count > 0 {
                            var startMonth = 1
                            var endMonth = 12
                            
                            while startMonth != endMonth {
                                let mid = (startMonth + endMonth) / 2
                                
                                let start = Calendar.iso8601.date(from: DateComponents(year: year, month: startMonth, day: 1))!
                                let end = Calendar.iso8601.date(from: DateComponents(year: year, month: mid + 1, day: 1))!.addSeconds(-1)

                                let _transactions = try await api.getCardTransactions(cardNo: campusCard.cardNo, beginDate: Int(start.timeIntervalSince1970) * 1000, endDate: Int(end.timeIntervalSince1970) * 1000)
                                
                                if _transactions.1.count > 0 {
                                    endMonth = mid
                                } else {
                                    startMonth = mid + 1
                                }
                            }
                            
                            self.startMonth = DateComponents(year: year, month: startMonth)
                            break
                        }
                    }
                    
                    mode = .monthly(year: Date.now.get(.year).year!, month: Date.now.get(.month).month!)
                } catch {
                    print(error)
                }
            }
        }
    }
}

