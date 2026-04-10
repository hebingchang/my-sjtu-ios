//
//  SelfStudyRoomStatusTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class SelfStudyRoomRealtimeStatusToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_self_study_room_status",
                displayName: "查询教室实时状态",
                category: .query,
                functionDescription: "根据教室 ID 查询该教室的实时状态详情，返回所在位置、当前状态、在室人数、参考节次、今日课程、节次详情、实时环境和设施信息。",
                parametersSchema: .selfStudyRoomStatus,
                isAvailableInChat: true,
                requiresUserAuthorization: false
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let arguments = try JSONDecoder().decode(
                    SelfStudyRoomStatusToolArguments.self,
                    from: Data(argumentsJSON.utf8)
                )
                let api = SelfStudyClassroomAPI()

                guard let snapshot = try await api.fetchRealtimeRoomSnapshot(roomId: arguments.roomId) else {
                    return AIService.encodeToolExecutionError(
                        .init(error: "未找到 ID 为 \(arguments.roomId) 的教室。")
                    )
                }

                let currentStatus = api.roomStatus(for: snapshot.room, in: snapshot)

                async let panoramaTask = api.fetchRoomPanoramaXMLURL(roomId: snapshot.room.id)
                async let attributesTask = api.fetchRoomAttributes(roomId: snapshot.room.id)
                async let environmentTask = api.fetchRoomEnvironmental(roomId: snapshot.room.id)

                var warnings: [String] = []
                var hasPanorama = false
                var facilities: [SelfStudyRoomRealtimeStatusToolResult.Facility] = []
                var hasEnvironmentSensor = false
                var environmentMetrics: [SelfStudyRoomRealtimeStatusToolResult.EnvironmentMetric] = []

                do {
                    hasPanorama = try await panoramaTask != nil
                } catch {
                    warnings.append("360 全景：\(AIService.selfStudyClassroomErrorText(error))")
                }

                do {
                    let attributes = try await attributesTask
                    facilities = attributes
                        .filter { $0.code.uppercased() != "ROOM_ATTR_360" }
                        .map {
                            .init(
                                name: $0.name,
                                value: $0.value
                            )
                        }
                } catch {
                    warnings.append("教室属性：\(AIService.selfStudyClassroomErrorText(error))")
                }

                do {
                    let environment = try await environmentTask
                    hasEnvironmentSensor = environment.hasSensor
                    environmentMetrics = AIService.selfStudyEnvironmentMetrics(from: environment)
                } catch {
                    warnings.append("实时环境：\(AIService.selfStudyClassroomErrorText(error))")
                }

                let sectionDetails = snapshot.sections.map { section in
                    let status = api.roomStatus(
                        for: snapshot.room,
                        in: snapshot,
                        at: section.sectionIndex
                    )

                    return SelfStudyRoomRealtimeStatusToolResult.SectionDetail(
                        sectionIndex: section.sectionIndex,
                        startTime: section.startTime,
                        endTime: section.endTime,
                        status: status.statusText,
                        course: status.currentCourse.map {
                            AIService.selfStudyToolCourseInfo(from: $0)
                        }
                    )
                }

                let todayCourses = snapshot.room.courses
                    .sorted {
                        if $0.startSection != $1.startSection {
                            return $0.startSection < $1.startSection
                        }
                        return $0.endSection < $1.endSection
                    }
                    .map { AIService.selfStudyToolCourseInfo(from: $0) }

                let result = SelfStudyRoomRealtimeStatusToolResult(
                    roomId: snapshot.room.id,
                    roomName: snapshot.room.name,
                    campusName: snapshot.campusName,
                    buildingName: snapshot.building.name,
                    floorName: snapshot.floor.name,
                    status: currentStatus.statusText,
                    currentStudentCount: snapshot.room.actualStudentCount,
                    referenceSection: AIService.selfStudyToolSectionInfo(from: snapshot.currentSection),
                    currentCourse: currentStatus.currentCourse.map {
                        AIService.selfStudyToolCourseInfo(from: $0)
                    },
                    hasEnvironmentSensor: hasEnvironmentSensor,
                    environmentMetrics: environmentMetrics,
                    hasPanorama: hasPanorama,
                    facilities: facilities,
                    sectionDetails: sectionDetails,
                    todayCourses: todayCourses,
                    warnings: warnings.isEmpty ? nil : warnings
                )

                return AIService.encodeToolExecutionResult(result)
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: AIService.selfStudyClassroomErrorText(error))
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            guard let roomId = parsedRoomId(argumentsJSON: argumentsJSON) else {
                return await super.invocationStatusPayload(argumentsJSON: argumentsJSON)
            }

            let api = SelfStudyClassroomAPI()
            let roomDisplayName = (try? await api.fetchRoomDisplayName(roomId: roomId))?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let resolvedQueryName: String
            if let roomDisplayName, !roomDisplayName.isEmpty {
                resolvedQueryName = roomDisplayName
            } else {
                resolvedQueryName = "教室 \(roomId)"
            }

            return .init(
                text: "已调用“查询\(resolvedQueryName)实时状态”",
                functionName: functionName,
                category: category,
                invocationKey: "\(functionName)|room_id=\(roomId)"
            )
        }

        private func parsedRoomId(argumentsJSON: String) -> Int? {
            guard let arguments = try? JSONDecoder().decode(
                SelfStudyRoomStatusToolArguments.self,
                from: Data(argumentsJSON.utf8)
            ) else {
                return nil
            }

            return arguments.roomId
        }
    }
}
