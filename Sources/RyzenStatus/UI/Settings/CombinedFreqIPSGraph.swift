import SwiftUI

struct CombinedFreqIPSGraph: View {
    let freqHistory: [Double]
    let ipsHistory: [Double]
    let capacity: Int = 60
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            
            ZStack(alignment: .bottomLeading) {
                // Background grid lines (optional)
                VStack {
                    Divider()
                    Spacer()
                    Divider()
                    Spacer()
                    Divider()
                }
                .opacity(0.1)
                
                // IPS (GIPS) - 0 a 500 GIPS
                Path { path in
                    let values = ipsHistory
                    let count = capacity
                    let startIdx = count - values.count
                    
                    if values.isEmpty { return }
                    
                    var firstX: CGFloat = 0
                    var lastX: CGFloat = 0
                    
                    for i in 0..<values.count {
                        let x = width * CGFloat(startIdx + i) / CGFloat(max(1, count - 1))
                        let y = height * (1.0 - CGFloat(min(max(values[i], 0), 500.0)) / 500.0)
                        
                        if i == 0 {
                            firstX = x
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        lastX = x
                    }
                    
                    path.addLine(to: CGPoint(x: lastX, y: height))
                    path.addLine(to: CGPoint(x: firstX, y: height))
                    path.closeSubpath()
                }
                .fill(Color.green.opacity(0.25))
                
                // Frecuencia (GHz) - 0 a 6 GHz
                Path { path in
                    let values = freqHistory
                    let count = capacity
                    let startIdx = count - values.count
                    
                    if values.isEmpty { return }
                    
                    for i in 0..<values.count {
                        let x = width * CGFloat(startIdx + i) / CGFloat(max(1, count - 1))
                        let y = height * (1.0 - CGFloat(min(max(values[i], 0), 6.0)) / 6.0)
                        
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 2)
            }
        }
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
