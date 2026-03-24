//
//  CampusCardListView.swift
//  MySJTU
//
//  Created by 何炳昌 on 2024/12/14.
//

import SwiftUI
import Alamofire

struct BusListView: View {
    @State private var loading: Bool = true
    @State private var lines: [BusLine] = []

    var body: some View {        
        ZStack {
            if loading {
                VStack {
                    ProgressView()
                }
            } else {
                List {
                    Section(header: Text("线路")) {
                        ForEach(lines, id: \.id) { line in
                            NavigationLink {
                                BusMapView(selectedLine: line)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(line.name)
                                    if line.startStation == line.endStation {
                                        Text(line.direction == 0 ? "顺时针" : "逆时针")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(line.startStation) → \(line.endStation)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                    Section(header: Text("收藏")) {
                    }
                }
            }
        }
        .animation(.easeInOut, value: loading)
        .navigationTitle("校园巴士")
        .task {
            do {
                lines = try await AF.request("https://campuslife.sjtu.edu.cn/api/v1/shuttle")
                    .serializingDecodable(BusResponse<BusLine>.self)
                    .value
                    .data
                    .filter({ line in
                        line.lineCode == "918484"
                    })
                loading = false
            } catch {
                print(error)
            }
        }
    }
}

#Preview {
    BusListView()
}
