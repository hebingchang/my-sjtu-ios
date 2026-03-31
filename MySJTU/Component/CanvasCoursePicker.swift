//
//  CanvasCoursePicker.swift
//  MySJTU
//
//  Created by boar on 2026/03/28.
//

import SwiftUI
import GRDB
import Apollo

struct CanvasCourseOption: Identifiable, Equatable {
    let id: String
    let legacyID: String
    let name: String
    let courseCode: String?
    let termID: String?
    let termName: String

    init(course: CanvasSchema.GetAllClassesQuery.Data.AllCourse) {
        id = course.id
        legacyID = course._id
        name = course.name
        courseCode = course.courseCode
        termID = course.term?._id
        termName = Self.normalizedTermName(course.term?.name)
    }

    var termIDValue: Int? {
        guard let termID else {
            return nil
        }
        return Int(termID)
    }

    var displayName: String {
        guard let courseCode, !courseCode.isEmpty else {
            return name
        }
        return "\(name) (\(courseCode))"
    }

    private static func normalizedTermName(_ termName: String?) -> String {
        guard let termName, !termName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "未标注学期"
        }
        return termName
    }
}

struct CanvasCourseTermSection: Identifiable {
    let id: String
    let title: String
    let courses: [CanvasCourseOption]
}

extension Array where Element == CanvasCourseOption {
    var idDictionary: [String: CanvasCourseOption] {
        Dictionary(uniqueKeysWithValues: map { ($0.id, $0) })
    }

    var groupedByTermSections: [CanvasCourseTermSection] {
        let grouped = Dictionary(grouping: self, by: \.termName)
        let orderedTermNames = grouped.keys.sorted { lhs, rhs in
            let lhsTermID = grouped[lhs]?.compactMap(\.termIDValue).max() ?? Int.min
            let rhsTermID = grouped[rhs]?.compactMap(\.termIDValue).max() ?? Int.min

            if lhsTermID != rhsTermID {
                return lhsTermID > rhsTermID
            }

            return lhs.localizedCompare(rhs) == .orderedAscending
        }

        return orderedTermNames.compactMap { termName in
            guard let courses = grouped[termName] else {
                return nil
            }

            return CanvasCourseTermSection(
                id: termName,
                title: termName,
                courses: courses.sorted { lhs, rhs in
                    if lhs.name != rhs.name {
                        return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.id < rhs.id
                }
            )
        }
    }
}

extension CanvasAPI {
    func getAllCourseOptions() async throws -> [CanvasCourseOption] {
        try await getAllClasses().map { CanvasCourseOption(course: $0) }
    }
}

struct CanvasCourseSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String?
    let canvasCourseSections: [CanvasCourseTermSection]
    var isLoading: Bool = false
    var loadErrorMessage: String?
    var emptyDescription: String = "当前账户下暂无可供匹配的 Canvas 课程。"
    var onRetry: (() async -> Void)?

    var body: some View {
        Group {
            if isLoading && canvasCourseSections.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadErrorMessage {
                ContentUnavailableView(
                    "无法加载 Canvas 课程",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadErrorMessage)
                )
            } else if canvasCourseSections.isEmpty {
                ContentUnavailableView(
                    "暂无 Canvas 课程",
                    systemImage: "books.vertical",
                    description: Text(emptyDescription)
                )
            } else {
                List {
                    Section(header: Text("匹配状态")) {
                        Button {
                            selection = nil
                            dismiss()
                        } label: {
                            selectionRow(
                                title: "未匹配",
                                subtitle: "移除当前 Canvas 课程匹配",
                                isSelected: selection == nil
                            )
                        }
                    }

                    ForEach(canvasCourseSections) { section in
                        Section(header: Text(section.title)) {
                            ForEach(section.courses) { canvasCourse in
                                Button {
                                    selection = canvasCourse.id
                                    dismiss()
                                } label: {
                                    selectionRow(
                                        title: canvasCourse.name,
                                        subtitle: canvasCourse.courseCode,
                                        isSelected: selection == canvasCourse.id
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择 Canvas 课程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if loadErrorMessage != nil, let onRetry {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重试") {
                        Task {
                            await onRetry()
                        }
                    }
                }
            }
        }
    }

    private func selectionRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color(UIColor.label))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

extension CanvasClass {
    static func latestMatch(for classID: String, college: College, in db: Database) throws -> CanvasClass? {
        try CanvasClass
            .filter(Column("college") == college && Column("class_id") == classID)
            .fetchAll(db)
            .last
    }

    static func replaceMatch(_ canvasCourseID: String?, for classID: String, college: College, in db: Database) throws {
        try CanvasClass
            .filter(Column("college") == college && Column("class_id") == classID)
            .deleteAll(db)

        guard let canvasCourseID else {
            return
        }

        try CanvasClass(id: canvasCourseID, college: college, class_id: classID).save(db)
    }
}
