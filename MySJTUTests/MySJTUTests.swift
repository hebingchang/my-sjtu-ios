//
//  MySJTUTests.swift
//  MySJTUTests
//
//  Created by boar on 2024/09/28.
//

import Foundation
import Testing
@testable import MySJTU

struct MySJTUTests {
    @Test func userProfileToolPrefersDefaultNormalIdentity() async throws {
        let profile = Profile(
            id: "1",
            account: "test",
            accountPhotoUrl: nil,
            name: " 张三 ",
            kind: "person",
            code: "fallback",
            userType: "student",
            organize: Organize(name: "学校", id: "root"),
            identities: [
                Identity(
                    kind: "identity",
                    isDefault: false,
                    createDate: 10,
                    code: "20230001",
                    userType: "student",
                    userTypeName: "本科生",
                    organize: Organize(name: "电子信息与电气工程学院", id: "1"),
                    status: "正常",
                    expireDate: nil,
                    classNo: "F2301001",
                    admissionDate: "2023-09-01",
                    trainLevel: "本科",
                    graduateDate: "2027-06-30",
                    photoUrl: nil,
                    type: nil
                ),
                Identity(
                    kind: "identity",
                    isDefault: true,
                    createDate: 5,
                    code: "T0001",
                    userType: "faculty",
                    userTypeName: "教师",
                    organize: Organize(name: "教务处", id: "2"),
                    status: "正常",
                    expireDate: nil,
                    classNo: nil,
                    admissionDate: nil,
                    trainLevel: nil,
                    graduateDate: nil,
                    photoUrl: nil,
                    type: nil
                )
            ]
        )

        let result = AIService.makeUserProfileToolResult(from: profile)

        #expect(result.name == "张三")
        #expect(result.code == "T0001")
        #expect(result.userTypeName == "教师")
        #expect(result.organize == "教务处")
        #expect(result.classNo == nil)
        #expect(result.admissionDate == nil)
        #expect(result.trainLevel == nil)
        #expect(result.graduateDate == nil)
    }

    @Test func userProfileToolOmitsFieldsWithoutNormalIdentityOrValue() async throws {
        let profile = Profile(
            id: "2",
            account: "test2",
            accountPhotoUrl: nil,
            name: " 李四 ",
            kind: "person",
            code: "20235555",
            userType: "student",
            organize: Organize(name: "学校", id: "root"),
            identities: [
                Identity(
                    kind: "identity",
                    isDefault: true,
                    createDate: 1,
                    code: "20235555",
                    userType: "student",
                    userTypeName: "研究生",
                    organize: Organize(name: "安泰经济与管理学院", id: "3"),
                    status: "冻结",
                    expireDate: nil,
                    classNo: " ",
                    admissionDate: " ",
                    trainLevel: nil,
                    graduateDate: nil,
                    photoUrl: nil,
                    type: nil
                )
            ]
        )

        let result = AIService.makeUserProfileToolResult(from: profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try String(
            decoding: encoder.encode(result),
            as: UTF8.self
        )

        #expect(result.name == "李四")
        #expect(result.code == nil)
        #expect(result.userTypeName == nil)
        #expect(result.organize == nil)
        #expect(!payload.contains("\"ok\""))
        #expect(!payload.contains("\"code\""))
        #expect(!payload.contains("\"userTypeName\""))
        #expect(!payload.contains("\"organize\""))
        #expect(!payload.contains("\"classNo\""))
        #expect(!payload.contains("\"admissionDate\""))
    }

    @Test func responsesStreamParserAcceptsConcatenatedRawJSONPayloads() async throws {
        var parser = SSEEventParser()

        let payloads = try parser.append(
            Data(
                """
                {"type":"response.output_text.delta","delta":"Hello"}{"type":"response.output_text.delta","delta":" world"} \t
                """.utf8
            )
        )
        let remainingPayloads = try parser.finish()

        #expect(payloads.count == 2)
        #expect(remainingPayloads.isEmpty)
        #expect(String(decoding: payloads[0], as: UTF8.self) == #"{"type":"response.output_text.delta","delta":"Hello"}"#)
        #expect(String(decoding: payloads[1], as: UTF8.self) == #"{"type":"response.output_text.delta","delta":" world"}"#)
    }

    @Test func responsesEventFallsBackToFinalResponseObjectText() async throws {
        let payload = Data(
            """
            {
              "id": "resp_123",
              "object": "response",
              "output": [
                {
                  "type": "message",
                  "role": "assistant",
                  "content": [
                    { "type": "output_text", "text": "Hello" },
                    { "type": "output_text", "text": " world" }
                  ]
                }
              ]
            }
            """.utf8
        )
        var accumulatedText = ""

        let updatedText = try AIService.processResponsesEvent(
            data: payload,
            accumulatedText: &accumulatedText
        )

        #expect(updatedText == "Hello world")
        #expect(accumulatedText == "Hello world")
    }

    @Test func toolSchemaStrictModeOnlyAppliesToFullyRequiredProperties() async throws {
        #expect(FunctionParametersSchema.academicYearSemester.supportsStrictMode)
        #expect(!FunctionParametersSchema.examAndGradeStatisticsRange.supportsStrictMode)
        #expect(!FunctionParametersSchema.deletePendingNotifications.supportsStrictMode)
    }

}
