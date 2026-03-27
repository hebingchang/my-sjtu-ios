//
//  CampusCardView.swift
//  MySJTU
//
//  Created by boar on 2024/12/14.
//

import SwiftUI
import Combine

struct NumberKeyboardView: View {
    @Binding var enteredCode: String
    
    let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]
    
    private struct NumberButtonStyle: ButtonStyle {
        @ViewBuilder
        func makeBody(configuration: Configuration) -> some View {
            let background = configuration.isPressed ? Color(UIColor.systemGray4) : Color(UIColor.systemBackground)

            configuration.label
                .foregroundColor(Color(UIColor.label))
                .background(background)
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach([20, 50, 100], id: \.self) { number in
                Button(action: {
                    enteredCode = String(number)
                }) {
                    Text("¥\(number)")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(NumberButtonStyle())
                .border(width: 0.5, edges: number == 50 ? [.top, .leading, .trailing] : [.top], color: Color(UIColor.systemGray4))
            }
            
            ForEach(1...9, id: \.self) { number in
                if [2, 5, 8].contains(number) {
                    Button(action: {
                        addDigit("\(number)")
                    }) {
                        Text("\(number)")
                            .font(.title)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(NumberButtonStyle())
                    .border(width: 0.5, edges: [.top, .leading, .trailing], color: Color(UIColor.systemGray4))
                } else {
                    Button(action: {
                        addDigit("\(number)")
                    }) {
                        Text("\(number)")
                            .font(.title)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(NumberButtonStyle())
                    .border(width: 0.5, edges: [.top], color: Color(UIColor.systemGray4))
                }
            }
            
            // Empty placeholder for layout alignment
            Spacer()
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .border(width: 0.5, edges: [.top], color: Color(UIColor.systemGray4))

            // Zero Button
            Button(action: {
                addDigit("0")
            }) {
                Text("0")
                    .font(.title)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(NumberButtonStyle())
            .border(width: 0.5, edges: [.top, .leading, .trailing], color: Color(UIColor.systemGray4))

            // Delete Button
            Button(action: {
                deleteDigit()
            }) {
                Image(systemName: "delete.left")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(NumberButtonStyle())
            .border(width: 0.5, edges: [.top], color: Color(UIColor.systemGray4))
        }
    }
    
    // MARK: - Actions
    
    private func addDigit(_ digit: String) {
        enteredCode.append(digit)
    }
    
    private func deleteDigit() {
        guard !enteredCode.isEmpty else { return }
        enteredCode.removeLast()
    }
}

struct CardChargeView: View {
    let campusCard: CampusCard
    @Binding var chargeOrderId: Int64?
    @State private var amount: Int = 0
    @State private var cardShake: Bool = false
    @State private var showChargeSheet: Bool = false
    @State private var chargeRequest: CardChargeResponse?
    @State private var loading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []

    var body: some View {
        let account = accounts.first {
            $0.provider == .jaccount
        }

        VStack {
            VStack(spacing: 48) {
                Image(uiImage: UIImage(named: "campus_card_front_small")!)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.36), radius: 16, x: 0, y: 5)
                    .offset(x: cardShake ? -30 : 0)

                VStack {
                    HStack(alignment: .top, spacing: 2) {
                        Text("¥")
                            .font(.system(size: 36, weight: .medium, design: .rounded))
                            .baselineOffset(-8)

                        Text("\(amount)")
                            .font(.system(size: 60, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    
                    if amount == 0 {
                        Text("当前余额 \(campusCard.cardBalance.formattedPrice(currency: "CNY"))")
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    } else if campusCard.cardBalance + Double(amount) <= 1000 {
                        Text("充值后余额 \((campusCard.cardBalance + Double(amount)).formattedPrice(currency: "CNY"))")
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    } else {
                        Text("最高余额 \((1000.0).formattedPrice(currency: "CNY"))")
                    }
                }
            }
            .padding()
            Spacer()
            if !loading {
                NumberKeyboardView(enteredCode: Binding(get: {
                    String(amount)
                }, set: { value in
                    if let value = Int(value) {
                        if Double(amount) + campusCard.cardBalance <= 1000 {
                            amount = value
                        } else if Double(value) + campusCard.cardBalance <= 1000 {
                            amount = value
                        }
                        
                        if Double(amount) + campusCard.cardBalance > 1000 {
                            withAnimation(.easeOut(duration: 0.05)) {
                                cardShake = true
                            } completion: {
                                withAnimation(Animation.spring(response: 0.2, dampingFraction: 0.2, blendDuration: 0.2)) {
                                    cardShake = false
                                }
                            }
                        }
                    } else {
                        amount = 0
                    }
                }))
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", role: .cancel) {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                if loading {
                    ProgressView()
                } else {
                    Button("添加") {
                        guard let account else {
                            return
                        }
                        
                        if amount > 0 && Double(amount) + campusCard.cardBalance <= 1000 {
                            Task {
                                do {
                                    withAnimation {
                                        loading = true
                                    }
                                    let api = SJTUOpenAPI(tokens: account.tokens)
                                    let request = try await api.chargeCampusCard(cardNo: campusCard.cardNo, amount: amount)
                                    print(request.id)
                                    chargeRequest = request
                                    showChargeSheet = true
                                } catch {
                                    print(error)
                                    
                                    if let error = error as? APIError {
                                        switch error {
                                        case .remoteError(let description):
                                            errorMessage = description
                                            showError = true
                                        default:
                                            break
                                        }
                                    }
                                    
                                    withAnimation {
                                        loading = false
                                    }
                                }
                            }
                        }
                    }
                    .disabled(amount == 0 || campusCard.cardBalance + Double(amount) > 1000)
                }
            }
        }
        .alert("充值失败", isPresented: $showError) {
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .sheet(
            isPresented: $showChargeSheet,
            onDismiss: {
                dismiss()
            }
        ) {
            if let chargeRequest, let queryString = chargeRequest.postData.toQueryString() {
                var urlRequest: URLRequest {
                    var request = URLRequest(url: URL(string: chargeRequest.postURL)!)
                    request.httpMethod = "POST"
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    request.httpBody = queryString.data(using: .utf8)
                    return request
                }

                BrowserView(
                    urlRequest: urlRequest,
                    redirectUrl: URL(string: "https://api.sjtu.edu.cn")!,
                    cookiesDomains: nil,
                    onRedirect: { (url, _, _) in
                        print(url)
                        chargeOrderId = chargeRequest.id
                        showChargeSheet = false
                    },
                    onlyCheckRedirectHost: true
                )
            }
        }
        .navigationTitle("充值")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CampusCardView: View {
    @Binding var campusCard: CampusCard
    let timer = Timer.publish(every: 5, on: .main, in: .common)

    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @AppStorage("card.enable_unicode") var showUnicode: Bool = false
    @Environment(\.scenePhase) var scenePhase

    @State private var photoUrl: String?
    @State private var loadingTransactions: Bool = false
    @State private var transactions: [CardTransaction] = []
    @State private var showCardTitle: Bool = false
    @State private var showChargeSheet: Bool = false
    @State private var timerSubscription: Cancellable? = nil
    @State private var chargeOrderId: Int64?
    
    @State private var cardNoMore = false
    @State private var unicodeNoMore = false
    private var noMore: Bool {
        return cardNoMore && (!enableUnicode || unicodeNoMore)
    }
    
    private var enableUnicode: Bool {
        let account = accounts.first { $0.provider == .jaccount }
        return showUnicode && (account?.enabledFeatures.contains(.unicode) ?? false)
    }

    private func loadTransactions(account: WebAuthAccount, isInit: Bool = false) async throws {
        if !isInit && (loadingTransactions || noMore) {
            return
        }
        
        if isInit {
            withAnimation {
                transactions = []
            }
        }
        
        loadingTransactions = true
        do {
            let api = SJTUOpenAPI(tokens: account.tokens)
            if enableUnicode {
                let lastDate = transactions.last?.dateTime
                
                var (_, cardTransactions) = try await api.getCardTransactions(cardNo: campusCard.cardNo, start: lastDate == nil ? 0 : nil, limit: 1, endDate: lastDate)
                var unicodeTransactions = try await api.getUnicodeTransactions(start: lastDate == nil ? 0 : nil, limit: 1, endDate: lastDate == nil ? nil : lastDate! / 1000)
                
                if cardTransactions.count == 0 {
                    cardNoMore = true
                }

                if unicodeTransactions.count == 0 {
                    unicodeNoMore = true
                }
                                
                if !cardNoMore, (unicodeNoMore || Date(timeIntervalSince1970: Double(unicodeTransactions.first!.orderTime)) <= Date(timeIntervalSince1970: Double(cardTransactions.first!.dateTime) / 1000)) {
                    (_, cardTransactions) = try await api.getCardTransactions(cardNo: campusCard.cardNo, start: lastDate == nil ? 0 : nil, limit: 20, endDate: lastDate)
                    if cardTransactions.count > 0, !unicodeNoMore {
                        unicodeTransactions = try await api.getUnicodeTransactions(beginDate: cardTransactions.last!.dateTime / 1000, endDate: lastDate)
                    }
                } else if !unicodeNoMore, (cardNoMore || Date(timeIntervalSince1970: Double(unicodeTransactions.first!.orderTime)) > Date(timeIntervalSince1970: Double(cardTransactions.first!.dateTime) / 1000)) {
                    unicodeTransactions = try await api.getUnicodeTransactions(start: lastDate == nil ? 0 : nil, limit: 20, endDate: lastDate == nil ? nil : lastDate! / 1000)
                    if unicodeTransactions.count > 0, !cardNoMore {
                        (_, cardTransactions) = try await api.getCardTransactions(cardNo: campusCard.cardNo, beginDate: unicodeTransactions.last!.orderTime * 1000, endDate: lastDate)
                    }
                }
                
                if isInit {
                    withAnimation {
                        transactions = (cardTransactions + unicodeTransactions.map({ $0.toCardTransaction() })).sorted(by: { $0.dateTime > $1.dateTime }).filter({ !transactions.contains($0) })
                    }
                } else {
                    withAnimation {
                        transactions += (cardTransactions + unicodeTransactions.map({ $0.toCardTransaction() })).sorted(by: { $0.dateTime > $1.dateTime }).filter({ !transactions.contains($0) })
                    }
                }
            } else {
                let (total, transactions) = try await api.getCardTransactions(cardNo: campusCard.cardNo, start: transactions.count, limit: 20)
                if isInit {
                    withAnimation {
                        self.transactions = transactions
                    }
                } else {
                    withAnimation {
                        self.transactions += transactions
                    }
                }
                
                if self.transactions.count >= total {
                    cardNoMore = true
                }
            }
        } catch {
            print(error)
        }
        loadingTransactions = false
    }
    
    private func loadUncompleteCharge(account: WebAuthAccount, id: Int64) async throws -> CardChargeStatus {
        let api = SJTUOpenAPI(tokens: account.tokens)
        return try await api.getChargeStatus(cardNo: campusCard.cardNo, orderId: id)
    }
    
    var body: some View {
        let account = accounts.first { $0.provider == .jaccount }
        
        var cardCover: String {
            switch campusCard.cardType {
            case .general:
                return "campus_card_blue"
            case .working:
                return "campus_card_work"
            case .undergraduate, .master, .doctor:
                return "campus_card_student"
            }
        }
        
        List {
            Image(uiImage: UIImage(named: cardCover)!)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    GeometryReader { geometry in
                        ZStack {
                            if let photoUrl {
                                AsyncImage(
                                    url: URL(string: photoUrl),
                                    transaction: Transaction(animation: .easeInOut)
                                ) { phase in
                                    if let image = phase.image {
                                        image.resizable()
                                            .aspectRatio(contentMode: .fit)
                                    }
                                }
                                .frame(width: geometry.size.width * 0.31)
                                .position(x: 0.23 * geometry.size.width, y: 0.62 * geometry.size.height)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                var userType: String {
                                    switch campusCard.cardType {
                                    case .undergraduate:
                                        return "本科生"
                                    case .master:
                                        return "硕士研究生"
                                    case .doctor:
                                        return "博士研究生"
                                    case .working:
                                        return "教工"
                                    default:
                                        return ""
                                    }
                                }
                                
                                Text("姓名：\(campusCard.user.name)")
                                Text("类别：\(userType)")
                                Text("学号：\(campusCard.user.code)")
                                Text("卡号：\(campusCard.cardNo)")
                            }
                            .foregroundStyle(Color.black)
                            .font(.callout)
                            .frame(width: geometry.size.width * 0.55)
                            .position(x: 0.68 * geometry.size.width, y: 0.62 * geometry.size.height)
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.gray.opacity(0.2))
                }
                .onAppear {
                        showCardTitle = false
                }
                .onDisappear {
                        showCardTitle = true
                }
            
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("余额")
                        Text(campusCard.cardBalance.formattedPrice(currency: "CNY"))
                            .font(.title)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                    }
                    
                    Spacer()
                    
                    Button("充值") {
                        showChargeSheet = true
                    }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .padding([.leading, .trailing])
                    .padding([.top, .bottom], 8)
                    .background(Color(UIColor.label))
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .clipShape(.capsule)
                }
            }
            
            if chargeOrderId != nil {
                Section {
                    VStack(alignment: .leading) {
                        Text("正在充值")
                            .fontWeight(.semibold)
                        Text("正在检查充值状态")
                            .font(.callout)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                }
            }
            
            Section(header: Text("近期交易")) {
                ForEach(transactions, id: \.self) { transaction in
                    HStack(spacing: 12) {
                        var backgroundColor: Color {
                            if transaction.amount > 0 {
                                Color.black
                            } else if transaction.amount < 0 {
                                Color.blue
                            } else {
                                Color.gray
                            }
                        }
                        
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(backgroundColor)
                            .frame(width: 40, height: 40)
                            .overlay {
                                VStack {
                                    if transaction.amount > 0 {
                                        Image(systemName: "chineseyuanrenminbisign")
                                    } else if transaction.amount < 0 {
                                        Image(systemName: "basket")
                                    } else {
                                        Image(systemName: "chineseyuanrenminbisign.bank.building")
                                    }
                                }
                                .font(.title2)
                                .foregroundStyle(Color.white)
                            }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text(transaction.description)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Spacer()
                                Group {
                                    if transaction.amount < 0 {
                                        Text("\((-transaction.amount).formattedPrice(currency: "CNY"))")
                                    } else if transaction.amount == 0 {
                                        Text(transaction.amount.formattedPrice(currency: "CNY"))
                                    } else {
                                        Text("+\(transaction.amount.formattedPrice(currency: "CNY"))")
                                    }
                                }
                                .font(.callout)
                                .fontDesign(.rounded)
                            }
                            if transaction.system != "" || transaction.merchant != "" {
                                Text("\(transaction.system)・\(transaction.merchant)")
                                    .font(.caption)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                            }
                            Text("\(Date(timeIntervalSince1970: Double(transaction.dateTime) / 1000).formattedRelativeDate())")
                                .font(.caption)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                    }
                    .onAppear {
                        if let last = transactions.last, transaction.dateTime == last.dateTime {
                            if let account {
                                Task {
                                    try await loadTransactions(account: account)
                                }
                            }
                        }
                    }
                }
                
                if loadingTransactions {
                    HStack {
                        Spacer()
                        ProgressView()
                            .id(UUID())
                            .padding()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .headerProminence(.increased)
        }
        .animation(.easeInOut, value: chargeOrderId)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ZStack {
                    let image = UIImage(named: "campus_card_front_small")!
                    Image(uiImage: image)
                        .antialiased(true)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 36)
                        .cornerRadius(2)
                        .opacity(showCardTitle ? 1 : 0)
                        .offset(y: showCardTitle ? 0 : 36)
                }
                .frame(width: 100)
                .animation(.spring, value: showCardTitle)
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Menu {
                    Button(action: {
                        showUnicode.toggle()
                    }) {
                        HStack {
                            Text("同时显示思源码消费记录")
                            Spacer()
                            if enableUnicode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Section {
                        NavigationLink {
                            CostAnalytics(campusCard: campusCard)
                        } label: {
                            Label("消费分析", systemImage: "chart.xyaxis.line")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(
            isPresented: $showChargeSheet
        ) {
            NavigationStack {
                CardChargeView(campusCard: campusCard, chargeOrderId: $chargeOrderId)
            }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                timerSubscription?.cancel()

                if chargeOrderId != nil {
                    timerSubscription = timer.connect()
                }
            default:
                break
            }
        }
        .onReceive(timer) { time in
            if let account {
                Task {
                    if let chargeOrderId {
                        do {
                            let charge = try await loadUncompleteCharge(account: account, id: chargeOrderId)
                            print(charge)
                            
                            switch charge.status.code {
                            case "RECHARGED":
                                // 充值成功
                                do {
                                    let api = SJTUOpenAPI(tokens: account.tokens)
                                    let cards = try await api.getCampusCards()
                                    if let card = cards.first(where: { $0.cardNo == charge.cardNo }) {
                                        self.campusCard.cardBalance = card.cardBalance
                                    }
                                    try await loadTransactions(account: account, isInit: true)
                                    print("success")
                                } catch {
                                    print(error)
                                }
                                
                                self.chargeOrderId = nil
                            case "APPLY_PENDING", "PAY_PENDING", "RECHARGE_PENDING", "RECHARGING":
                                // 待充值, 充值处理中
                                break
                            case "PAY_FAILED":
                                if let reason = charge.failedReason, reason == "主动查询支付状态" {
                                    // still pending
                                } else {
                                    self.chargeOrderId = nil
                                }
                            case "APPLY_FAILED", "RECHARGE_FAILED":
                                // 申请失败, 支付失败, 充值失败
                                self.chargeOrderId = nil
                            default:
                                break
                            }
                        } catch {
                            print(error)
                        }
                    }
                }
            }
        }
        .onChange(of: chargeOrderId) {
            timerSubscription?.cancel()

            if chargeOrderId != nil {
                timerSubscription = timer.connect()
            }
        }
        .onChange(of: enableUnicode) {
            if let account {
                Task {
                    do {
                        try await loadTransactions(account: account, isInit: true)
                    } catch {
                        print(error)
                    }
                }
            }
        }
        .onFirstAppear {
            if let account {
                Task {
                    do {
                        let api = SJTUOpenAPI(tokens: account.tokens)
                        photoUrl = try await api.getCardPhoto(cardNo: campusCard.cardNo)
                    } catch {
                        print(error)
                    }
                }
            }
        }
        .onFirstAppear {
            if let account {
                Task {
                    try await loadTransactions(account: account)
                }
            }
        }
    }
}
