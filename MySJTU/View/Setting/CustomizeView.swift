//
//  CustomizeView.swift
//  MySJTU
//
//  Created by boar on 2024/11/26.
//

import SwiftUI

struct CustomizeView: View {
    @AppStorage("settings.always_show_unicode_in_tabbar") var alwaysShowUnicode: Bool = true
    @AppStorage("settings.schedule.auto_hide_week_label_overlay") var autoHideWeekLabelOverlay: Bool = true

    var body: some View {
        List {
            Section(header: Text("日程")) {
                NavigationLink {
                    ScheduleBackgroundImageView()
                } label: {
                    Label("日程页背景图片", systemImage: "photo.on.rectangle.angled")
                }

                HStack {
                    Text("滑动时自动隐藏学期标签")
                    Spacer()
                    Toggle(isOn: Binding(
                        get: {
                            autoHideWeekLabelOverlay
                        },
                        set: { newValue in
                            autoHideWeekLabelOverlay = newValue
                        }
                    )) {}
                }
            }

            Section(header: Text("小组件")) {
                NavigationLink {
                    WidgetBackgroundImageSettingsView()
                } label: {
                    Label("桌面小组件背景", systemImage: "square.grid.2x2")
                }
            }

            Section(header: Text("标签栏")) {
                HStack {
                    Text("始终显示思源码标签")
                    Spacer()
                    Toggle(isOn: Binding(
                        get: {
                            alwaysShowUnicode
                        },
                        set: { newValue in
                            alwaysShowUnicode = newValue
                        }
                    )) {}
                }
            }
        }
        .navigationBarTitle("个性化")
    }
}

#Preview {
    CustomizeView()
}
