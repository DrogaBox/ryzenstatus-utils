// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import Foundation

/// Linear regression math helper for trend analysis.
enum LinearRegression {
    struct Fit: Sendable, Equatable {
        let slope: Double
        let intercept: Double
        let rSquared: Double
    }

    /// Fits a line (y = slope * x + intercept) over a set of 2D points.
    /// Returns nil if there are fewer than 2 points or zero variance in x.
    static func fit(_ points: [(x: Double, y: Double)]) -> Fit? {
        let count = Double(points.count)
        guard count >= 2 else { return nil }

        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        let meanX = sumX / count
        let meanY = sumY / count

        var ssXX = 0.0
        var ssYY = 0.0
        var ssXY = 0.0

        for pt in points {
            let dx = pt.x - meanX
            let dy = pt.y - meanY
            ssXX += dx * dx
            ssYY += dy * dy
            ssXY += dx * dy
        }

        guard ssXX > 0.00001 else { return nil }

        let slope = ssXY / ssXX
        let intercept = meanY - slope * meanX

        let rSquared: Double
        if ssYY <= 0.00001 {
            rSquared = 1.0
        } else {
            let num = ssXY * ssXY
            let den = ssXX * ssYY
            rSquared = min(max(num / den, 0.0), 1.0)
        }

        return Fit(slope: slope, intercept: intercept, rSquared: rSquared)
    }
}

/// Flags a process whose memory footprint shows sustained, consistent upward growth
/// (a likely leak), while avoiding false positives from normal warm-up spikes.
enum LeakDetector {
    struct Config: Sendable {
        /// Minimum span of growth data required before judging (seconds).
        var minimumDuration: TimeInterval
        /// Minimum growth rate in bytes/second.
        var minimumSlope: Double
        /// Minimum R² fit: growth must be consistent, not a one-off jump.
        var minimumRSquared: Double
        /// Minimum number of samples.
        var minimumSamples: Int
        /// Minimum total growth across the window (bytes).
        var minimumTotalGrowth: UInt64

        init(
            minimumDuration: TimeInterval = 1200, // 20 minutes
            minimumSlope: Double = 8192,         // ~8 KB/s
            minimumRSquared: Double = 0.85,
            minimumSamples: Int = 10,
            minimumTotalGrowth: UInt64 = 33_554_432 // 32 MB
        ) {
            self.minimumDuration = minimumDuration
            self.minimumSlope = minimumSlope
            self.minimumRSquared = minimumRSquared
            self.minimumSamples = minimumSamples
            self.minimumTotalGrowth = minimumTotalGrowth
        }

        static let `default` = Config()
    }

    struct Finding: Sendable, Equatable {
        /// Growth rate in bytes/second.
        let slopeBytesPerSecond: Double
        /// Consistency of the trend (0...1).
        let rSquared: Double
        /// Span of the analyzed window in seconds.
        let durationSeconds: TimeInterval
        /// Total growth across the window in bytes.
        let totalGrowth: UInt64
        /// Confidence level (0...1).
        let confidence: Double
    }

    /// Analyzes a footprint time-series. Returns a `Finding` when the series meets
    /// every threshold for a likely leak, otherwise nil.
    static func analyze(series: [(Date, UInt64)], config: Config = .default) -> Finding? {
        guard series.count >= config.minimumSamples else { return nil }
        let sorted = series.sorted { $0.0 < $1.0 }
        guard let first = sorted.first, let last = sorted.last else { return nil }

        let duration = last.0.timeIntervalSince(first.0)
        guard duration >= config.minimumDuration else { return nil }

        let t0 = first.0.timeIntervalSince1970
        let points = sorted.map { (x: $0.0.timeIntervalSince1970 - t0, y: Double($0.1)) }
        guard let fit = LinearRegression.fit(points) else { return nil }

        guard fit.slope >= config.minimumSlope, fit.rSquared >= config.minimumRSquared else {
            return nil
        }

        let totalGrowth: UInt64 = last.1 > first.1 ? last.1 - first.1 : 0
        guard totalGrowth >= config.minimumTotalGrowth else { return nil }

        let slopeHeadroom = min(fit.slope / (config.minimumSlope * 8), 1.0)
        let confidence = max(0.0, min(0.6 * fit.rSquared + 0.4 * slopeHeadroom, 1.0))

        return Finding(
            slopeBytesPerSecond: fit.slope,
            rSquared: fit.rSquared,
            durationSeconds: duration,
            totalGrowth: totalGrowth,
            confidence: confidence
        )
    }
}
