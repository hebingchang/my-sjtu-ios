//
//  CampusCardListView.swift
//  MySJTU
//
//  Created by 何炳昌 on 2024/12/14.
//

import SwiftUI

struct CampusCardListView: View {
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var loading: Bool = true
    @State private var cards: [CampusCard] = []
    
    private func addCardType(cards: [CampusCard], profile: Profile) -> [CampusCard] {
        var cardsWithType = cards
        
        for i in 0..<cardsWithType.count {
            let card = cardsWithType[i]
            let identities = profile.identities.filter { $0.code == card.user.code }
            if identities.count > 0 {
                if let _ = identities.first(where: { $0.userType == "faculty" && $0.type != nil && !$0.type!.id.hasPrefix("4") && !$0.type!.id.hasPrefix("6") }) {
                    cardsWithType[i].cardType = .working
                } else if let _ = identities.first(where: { $0.userType == "postphd" }) {
                    cardsWithType[i].cardType = .working
                } else if let _ = identities.first(where: { $0.userType == "student" && $0.type != nil && ($0.type!.id.hasPrefix("10") || $0.type!.id.hasPrefix("11")) }) {
                    cardsWithType[i].cardType = .undergraduate
                } else if let _ = identities.first(where: { $0.userType == "student" && $0.type != nil && $0.type!.id.hasPrefix("2") && !$0.type!.id.hasPrefix("23") }) {
                    cardsWithType[i].cardType = .master
                } else if let _ = identities.first(where: { $0.userType == "student" && $0.type != nil && $0.type!.id.hasPrefix("3") }) {
                    cardsWithType[i].cardType = .doctor
                }
            }
        }
        
        return cardsWithType
    }

    var body: some View {
        let account = accounts.first { $0.provider == .jaccount }
        
        ZStack {
            if loading {
                VStack {
                    ProgressView()
                }
            } else {
                List {
                    Section(header: Text("有效的校园卡")) {
                        ForEach(Array(cards.enumerated()), id: \.element.cardNo) { index, card in
                            NavigationLink {
                                CampusCardView(campusCard: Binding(get: {
                                    card
                                }, set: { value in
                                    cards[index] = value
                                }))
                            } label: {
                                HStack(spacing: 10) {
                                    Image(uiImage: UIImage(named: "campus_card_front_small")!)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 42)
                                        .cornerRadius(3)

                                    VStack(alignment: .leading, spacing: 0) {
                                        var cardType: String {
                                            switch card.cardType {
                                            case .general: return "校园卡"
                                            case .working: return "教工卡"
                                            case .undergraduate: return "本科生"
                                            case .master: return "硕士生"
                                            case .doctor: return "博士生"
                                            }
                                        }
                                        Text(cardType)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Spacer(minLength: 0)
                                        Text("\(card.cardNo)・\(card.cardBalance.formattedPrice(currency: "CNY"))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(height: 38)
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(.easeInOut, value: loading)
        .navigationTitle("校园卡")
        .task {
            if let account {
                do {
                    let api = SJTUOpenAPI(tokens: account.tokens)
                    let profile = try await api.getProfile()
                    cards = addCardType(cards: try await api.getCampusCards(), profile: profile)
                } catch {
                    print(error)
                }
            }
            loading = false
        }
    }
}

#Preview {
    CampusCardListView()
}
