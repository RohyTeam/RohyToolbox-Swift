//
//  WordPickerPanel.swift
//  toolbox
//
//  Created by Deerio on 2026/9/21.
//

import SwiftUI

/// The long-press popup for choosing which words of a text block to redact.
struct WordPickerPanel: View {
    let block: TextBlock
    @Binding var selected: Set<Int>
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var words: [String] {
        block.words().map(\.word)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            VStack(spacing: 12) {
                Text("Select Words")
                    .font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        Button {
                            if selected.contains(index) {
                                selected.remove(index)
                            } else {
                                selected.insert(index)
                            }
                        } label: {
                            Text(word)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selected.contains(index) ? Color.accentColor : Color.clear,
                                    in: .capsule
                                )
                                .overlay {
                                    Capsule().stroke(Color.accentColor)
                                }
                                .foregroundStyle(selected.contains(index) ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("Cancel", role: .cancel, action: onCancel)
                    Spacer()
                    Button("Done", action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .disabled(selected.isEmpty)
                }
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(32)
        }
    }
}

/// A minimal flow layout that wraps children into rows.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions(), subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = layout(in: bounds.size, subviews: subviews)
        for (index, position) in layout.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in size: CGSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            if x + subviewSize.width > size.width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += subviewSize.width + spacing
            rowHeight = max(rowHeight, subviewSize.height)
        }
        return (CGSize(width: size.width, height: y + rowHeight), positions)
    }
}
