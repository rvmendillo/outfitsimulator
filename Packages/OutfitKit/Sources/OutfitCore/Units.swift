import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum HeightFormatter {
    public static let centimetresPerInch = 2.54

    public static func feetAndInches(fromCentimetres cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / centimetresPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    public static func centimetres(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * centimetresPerInch
    }

    public static func string(fromCentimetres cm: Double, units: UnitSystem) -> String {
        switch units {
        case .metric:
            return "\(Int(cm.rounded())) cm"
        case .imperial:
            let (feet, inches) = feetAndInches(fromCentimetres: cm)
            return "\(feet)′ \(inches)″"
        }
    }
}
