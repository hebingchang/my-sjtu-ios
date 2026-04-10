//
//  CapabilityProbeTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class CapabilityProbeToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "capability_probe",
                displayName: "检测模型函数调用能力",
                category: .query,
                functionDescription: "用于检测当前模型是否支持函数调用。",
                parametersSchema: .capabilityProbe,
                isAvailableInChat: false
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            AIService.encodeToolExecutionError(
                .init(error: "此工具仅用于检测模型是否支持函数调用。")
            )
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            .init(
                text: "已调用“\(displayName)”",
                functionName: functionName,
                category: category,
                invocationKey: functionName
            )
        }
    }
}
