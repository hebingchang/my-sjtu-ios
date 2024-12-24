//
//  DataSourceView.swift
//  MySJTU
//
//  Created by boar on 2024/12/04.
//

import SwiftUI
import WidgetKit

struct DataSourceView: View {
    @AppStorage("collegeId", store: UserDefaults.shared) var collegeId: College = .sjtu
    @AppStorage("showBothCollege", store: UserDefaults.shared) var showBothCollege: Bool = false

    private let colleges = [
        CollegeItem(id: College.sjtu, name: "本部（本科）"),
        CollegeItem(id: College.sjtug, name: "本部（研究生）"),
        CollegeItem(id: College.shsmu, name: "医学院"),
    ]

    var body: some View {
        List {
            ForEach(colleges, id: \.id) { college in
                Button {
                    collegeId = college.id
                } label: {
                    HStack {
                        Text(college.name)
                            .foregroundStyle(Color(UIColor.label))
                        Spacer()
                        if college.id == collegeId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            if collegeId == .sjtu {
                Section(header: Text("高级选项")) {
                    Toggle(isOn: $showBothCollege) {
                        VStack(alignment: .leading) {
                            Text("同时显示研究生课表")
                            Text("适用于本科生预选研究生课程")
                                .font(.footnote)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                    }
                }
            }
        }
        .navigationTitle("数据源")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: collegeId) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

#Preview {
    DataSourceView()
}
