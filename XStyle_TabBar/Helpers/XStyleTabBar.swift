//
//  XStyleTabBar.swift
//  XStyle_TabBar
//
//  Created by Balaji Venkatesh on 28/07/26.
//

import SwiftUI

/// TabItem Protocol
protocol XStyleTabItem: CaseIterable, Hashable {
    var title: String { get }
    var symbol: String { get }
}

struct XStyleTabBar<Value: XStyleTabItem>: View {
    /// Act's as Scroll Progress!
    var progress: CGFloat
    var onTap: (Value) -> ()
    /// View Properties
    @State private var titleWidth: [Value: CGFloat] = [:]
    @State private var tabLocation: [Value: CGRect] = [:]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.title) { tab in
                let index = CGFloat(tabs.firstIndex(of: tab) ?? 0)
                let tabProgress = min(abs(cappedProgress - index), 1)
                
                if tab != tabs.first {
                    Spacer(minLength: 0)
                        .frame(height: 30)
                        .contentShape(.rect)
                        .onTapGesture {
                            onTap(tab)
                        }
                }
                
                if let tabTitleWidth = titleWidth[tab] {
                    HStack(spacing: 0) {
                        ZStack {
                            Image(systemName: tab.symbol)
                                .foregroundStyle(.gray)
                                .opacity(tabProgress)
                            
                            Image(systemName: tab.symbol)
                                .foregroundStyle(Color.primary)
                                .opacity(1 - tabProgress)
                        }
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 25, height: 30, alignment: .leading)
                        /// Using Symbol to find tab's minX and tab width instead of using whole HStack, as it's resizing while scrolling!
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .named("CONTAINER"))
                        } action: { newValue in
                            var newRect = newValue
                            newRect.size.width = newValue.width + tabTitleWidth
                            tabLocation[tab] = newRect
                        }
                        
                        Text(tab.title)
                            .font(.system(size: 16, weight: .semibold))
                            .opacity(1 - tabProgress)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(
                                width: tabTitleWidth * (1 - tabProgress),
                                alignment: .trailing
                            )
                            .lineLimit(1)
                            .mask {
                                Rectangle()
                                    .blur(radius: 5 * min(tabProgress * 5, 1))
                                    .padding(-2)
                            }
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        onTap(tab)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(tabProgress < 0.5 ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("history.tab.\(tab.title)")
                    .accessibilityAction {
                        onTap(tab)
                    }
                }
                
                if tab != tabs.last {
                    Spacer(minLength: 0)
                        .frame(height: 30)
                        .contentShape(.rect)
                        .onTapGesture {
                            onTap(tab)
                        }
                }
            }
        }
        .coordinateSpace(.named("CONTAINER"))
        .padding(.bottom, 6)
        .overlay(alignment: .bottomLeading) {
            /// Resizing Indicator
            if tabLocation.count == tabs.count {
                let extraWidth: CGFloat = 15
                let inputRange = tabs.indices.compactMap({ CGFloat($0) })
                let outputSizeRange = tabs.compactMap({
                    (tabLocation[$0]?.size.width ?? 0) + extraWidth
                })
                let outputLocationRange = tabs.compactMap({
                    (tabLocation[$0]?.minX ?? 0) - (extraWidth / 2)
                })
                
                let indicatorWidth = cappedProgress
                    .interpolate(inputRange: inputRange, outputRange: outputSizeRange)
                let indicatorOffset = cappedProgress
                    .interpolate(inputRange: inputRange, outputRange: outputLocationRange)
                
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: indicatorWidth, height: 2)
                    .offset(x: indicatorOffset)
            }
        }
        .onAppear {
            /// Calculating Title Width
            for tab in tabs {
                let width = NSString(string: tab.title).size(withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold)
                ]).width
                titleWidth[tab] = width
            }
        }
    }
    
    private var cappedProgress: CGFloat {
        max(min(progress, CGFloat(tabs.count - 1)), 0)
    }
    
    private var tabs: [Value] {
        Array(Value.allCases)
    }
}

/// Using Interpolation to interpolate input range to output range using progress!
fileprivate extension CGFloat {
    func interpolate(inputRange: [CGFloat], outputRange: [CGFloat]) -> CGFloat {
        /// If Value less than it's Initial Input Range
        let x = self
        let length = inputRange.count - 1
        if x <= inputRange[0] { return outputRange[0] }
        
        for index in 1...length {
            let x1 = inputRange[index - 1]
            let x2 = inputRange[index]
            
            let y1 = outputRange[index - 1]
            let y2 = outputRange[index]
            
            /// Linear Interpolation Formula: y1 + ((y2-y1) / (x2-x1)) * (x-x1)
            if x <= inputRange[index] {
                let y = y1 + ((y2-y1) / (x2-x1)) * (x-x1)
                return y
            }
        }
        
        /// If Value Exceeds it's Maximum Input Range
        return outputRange[length]
    }
}

#Preview {
    ContentView()
}
