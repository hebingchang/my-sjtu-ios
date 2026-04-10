//
//  SelfStudyBuildingRoomsTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class SelfStudyBuildingRoomsToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_self_study_building_rooms",
                displayName: "查询教学楼教室状态",
                category: .query,
                functionDescription: "根据教学楼名称查询该教学楼所有教室的当前状态。工具会在后台获取可用教学楼列表并解析教学楼名称，返回教室 ID、名称、楼层、在室人数、状态和当前课程。",
                parametersSchema: .selfStudyBuildingRooms,
                isAvailableInChat: true,
                requiresUserAuthorization: false
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let arguments = try JSONDecoder().decode(
                    SelfStudyBuildingRoomsToolArguments.self,
                    from: Data(argumentsJSON.utf8)
                )
                let api = SelfStudyClassroomAPI()
                let snapshot = try await api.fetchRealtimeBuildingSnapshot(named: arguments.buildingName)

                var availableRoomCount = 0
                let rooms = snapshot.floors.flatMap { floor in
                    floor.rooms.map { room -> SelfStudyBuildingRoomsToolResult.Room in
                        let status = api.roomStatus(for: room, in: snapshot)
                        if status.isAvailable {
                            availableRoomCount += 1
                        }

                        return .init(
                            id: room.id,
                            name: room.name,
                            floorName: floor.name,
                            currentStudentCount: room.actualStudentCount,
                            status: status.statusText,
                            currentCourse: status.currentCourse.map {
                                AIService.selfStudyToolCourseInfo(from: $0)
                            }
                        )
                    }
                }

                let result = SelfStudyBuildingRoomsToolResult(
                    campusName: snapshot.campusName,
                    buildingName: snapshot.building.name,
                    referenceSection: AIService.selfStudyToolSectionInfo(from: snapshot.currentSection),
                    roomCount: rooms.count,
                    availableRoomCount: availableRoomCount,
                    rooms: rooms
                )

                return AIService.encodeToolExecutionResult(result)
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: AIService.selfStudyClassroomErrorText(error))
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            guard let buildingName = parsedBuildingName(argumentsJSON: argumentsJSON) else {
                return await super.invocationStatusPayload(argumentsJSON: argumentsJSON)
            }

            return .init(
                text: "已调用“查询\(buildingName)教室状态”",
                functionName: functionName,
                category: category,
                invocationKey: "\(functionName)|building_name=\(buildingName)"
            )
        }

        private func parsedBuildingName(argumentsJSON: String) -> String? {
            guard let arguments = try? JSONDecoder().decode(
                SelfStudyBuildingRoomsToolArguments.self,
                from: Data(argumentsJSON.utf8)
            ) else {
                return nil
            }

            let trimmedName = arguments.buildingName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedName.isEmpty ? nil : trimmedName
        }
    }
}
