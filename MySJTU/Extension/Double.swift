//
//  Double.swift
//  MySJTU
//
//  Created by boar on 2024/11/23.
//

extension Double {
    var clean: String {
        return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }
}
