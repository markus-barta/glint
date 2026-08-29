import Foundation

struct OCRVisualRelationship: Hashable, Sendable {
    let lineGap: Int
    let isSameVisualLine: Bool
    let horizontalGap: Double?
    let centerDistance: Double?
}

/// Reconstructs visual rows from OCR geometry while preserving fragment order. Preserving order
/// is important: `sourceOrder` remains a stable bridge back to the original Vision fragment used
/// by scan highlighting, while `lineIndex` becomes a truthful visual-adjacency signal.
enum OCRVisualLayout {
    private struct LocatedFragment {
        let index: Int
        let region: OCRNormalizedRegion
    }

    private struct Row {
        var members: [LocatedFragment]

        var averageMidY: Double {
            members.map { $0.region.midY }.reduce(0, +) / Double(members.count)
        }

        var averageHeight: Double {
            members.map { $0.region.height }.reduce(0, +) / Double(members.count)
        }

        func affinity(with region: OCRNormalizedRegion) -> Double? {
            let representative = OCRNormalizedRegion(
                x: 0,
                y: averageMidY - averageHeight / 2,
                width: 1,
                height: averageHeight
            )
            guard sameVisualLine(representative, region) else { return nil }
            let overlap = verticalOverlap(representative, region)
            return overlap / max(0.000_001, min(representative.height, region.height))
        }
    }

    static func arranged(_ input: OCRContextInput) -> OCRContextInput {
        let located = input.fragments.enumerated().compactMap { index, fragment -> LocatedFragment? in
            guard let region = fragment.region?.validated else { return nil }
            return LocatedFragment(index: index, region: region)
        }
        guard !located.isEmpty else { return input }

        let readingOrder = located.sorted {
            if abs($0.region.midY - $1.region.midY) > 0.000_001 { return $0.region.midY > $1.region.midY }
            if abs($0.region.minX - $1.region.minX) > 0.000_001 { return $0.region.minX < $1.region.minX }
            return $0.index < $1.index
        }
        var rows: [Row] = []
        for item in readingOrder {
            let best = rows.indices.compactMap { index -> (Int, Double)? in
                rows[index].affinity(with: item.region).map { (index, $0) }
            }.max {
                if abs($0.1 - $1.1) > 0.000_001 { return $0.1 < $1.1 }
                return $0.0 > $1.0
            }
            if let best { rows[best.0].members.append(item) }
            else { rows.append(Row(members: [item])) }
        }
        rows.sort {
            if abs($0.averageMidY - $1.averageMidY) > 0.000_001 { return $0.averageMidY > $1.averageMidY }
            return ($0.members.map(\.index).min() ?? 0) < ($1.members.map(\.index).min() ?? 0)
        }

        var visualLineByFragment: [Int: Int] = [:]
        for (lineIndex, row) in rows.enumerated() {
            for member in row.members { visualLineByFragment[member.index] = lineIndex }
        }
        let firstFallbackLine = rows.count
        return OCRContextInput(fragments: input.fragments.enumerated().map { index, fragment in
            OCRContextFragment(
                text: fragment.text,
                lineIndex: visualLineByFragment[index] ?? firstFallbackLine + max(0, fragment.lineIndex),
                order: fragment.order,
                confidence: fragment.confidence,
                region: fragment.region
            )
        })
    }

    static func relationship(
        firstRegion: OCRNormalizedRegion?,
        firstLine: Int,
        secondRegion: OCRNormalizedRegion?,
        secondLine: Int
    ) -> OCRVisualRelationship {
        let lineGap = abs(firstLine - secondLine)
        guard let first = firstRegion?.validated, let second = secondRegion?.validated else {
            return OCRVisualRelationship(
                lineGap: lineGap,
                isSameVisualLine: lineGap == 0,
                horizontalGap: nil,
                centerDistance: nil
            )
        }
        let sameLine = sameVisualLine(first, second)
        let horizontalGap: Double
        if first.maxX < second.minX { horizontalGap = second.minX - first.maxX }
        else if second.maxX < first.minX { horizontalGap = first.minX - second.maxX }
        else { horizontalGap = 0 }
        return OCRVisualRelationship(
            lineGap: sameLine ? 0 : lineGap,
            isSameVisualLine: sameLine,
            horizontalGap: horizontalGap,
            centerDistance: hypot(first.midX - second.midX, first.midY - second.midY)
        )
    }

    private static func sameVisualLine(_ lhs: OCRNormalizedRegion, _ rhs: OCRNormalizedRegion) -> Bool {
        let overlapRatio = verticalOverlap(lhs, rhs) / max(0.000_001, min(lhs.height, rhs.height))
        let centerTolerance = max(lhs.height, rhs.height) * 0.46
        return overlapRatio >= 0.42 || abs(lhs.midY - rhs.midY) <= centerTolerance
    }

    private static func verticalOverlap(_ lhs: OCRNormalizedRegion, _ rhs: OCRNormalizedRegion) -> Double {
        max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
    }
}

private extension OCRNormalizedRegion {
    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    var validated: OCRNormalizedRegion? {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return nil }
        return self
    }
}
