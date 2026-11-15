import Foundation

/// Правила отрисовки числа в меню-баре.
///
/// Правило одно: слот под число всегда одной ширины. Иначе пункт меню-бара
/// меняет ширину при смене числа цифр, а вместе с ним едет открытая панель —
/// она привязана к кнопке в меню-баре.
public enum MenuBarLabel {
    /// Сколько знаков резервируем под число (до четырёх: «9999»).
    public static let numberSlots = 4

    /// Число в меню-баре: обычный вид до четырёх знаков, дальше — компактный.
    ///
    ///     0 → "0",  140 → "140",  1234 → "1234",  12345 → "12k"
    ///
    /// Результат всегда не длиннее `numberSlots`: иначе пункт меню-бара
    /// растёт и открытая панель смещается.
    public static func numberText(_ tps: Double) -> String {
        let value = max(0, tps)
        let rounded = value.rounded()
        if rounded < 10_000 { return String(Int(rounded)) }

        let units: [(Double, String)] = [(1_000, "k"), (1_000_000, "M"), (1_000_000_000, "G"), (1_000_000_000_000, "T")]
        for (scale, suffix) in units {
            let scaled = value / scale
            if scaled < 1000 { return "\(Int(scaled))\(suffix)" }
        }
        return "999T"
    }

    /// Строка под слот фиксированной ширины: число прижато вправо, чтобы
    /// последний знак не прыгал при изменении разрядности. Если измерений нет
    /// (простой или нет связи), в слоте стоит прочерк — пустое место выглядит
    /// как дыра в меню-баре.
    public static func slotText(_ tps: Double?) -> String {
        guard let tps else { return "--" }
        return numberText(tps)
    }
}
