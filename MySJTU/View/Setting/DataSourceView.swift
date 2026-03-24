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

    var body: some View {
        List {
            ForEach(categorizedColleges, id: \.category) { groupedCollege in
                Section(header: Text(groupedCollege.category)) {
                    ForEach(groupedCollege.colleges, id: \.id) { college in
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
