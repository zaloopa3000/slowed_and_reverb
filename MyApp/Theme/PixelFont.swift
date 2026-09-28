import SwiftUI

/// Hand-made 5×7 bitmap font (Latin, Cyrillic, digits, symbols) for the
/// arcade / dot-matrix look. Text is always rendered uppercase.
///
/// Each glyph is 7 rows of `#` (lit) / `.` (off); glyph width = row length,
/// so narrow glyphs like `.` or `!` take less space.
nonisolated enum PixelFont {
    static let glyphHeight = 7
    /// Empty columns between glyphs.
    static let letterSpacing = 1
    static let spaceWidth = 3

    /// Width of the text in font pixels.
    static func width(of text: String, bold: Bool = false) -> Int {
        let glyphs = Array(text.uppercased()).map(glyph(for:))
        guard !glyphs.isEmpty else { return 0 }
        let extra = bold ? 1 : 0
        let total = glyphs.reduce(0) { $0 + glyphWidth($1) + extra }
        return total + letterSpacing * (glyphs.count - 1)
    }

    /// Lit cells of the text, in font-pixel coordinates (x right, y down).
    static func cells(for text: String, bold: Bool = false) -> [(x: Int, y: Int)] {
        var result: [(x: Int, y: Int)] = []
        var cursor = 0
        for character in text.uppercased() {
            let rows = glyph(for: character)
            let width = glyphWidth(rows)
            for (y, row) in rows.enumerated() {
                for (x, bit) in row.enumerated() where bit == "#" {
                    result.append((cursor + x, y))
                    // Bold: every lit pixel also lights its right neighbour.
                    if bold { result.append((cursor + x + 1, y)) }
                }
            }
            cursor += width + (bold ? 1 : 0) + letterSpacing
        }
        return result
    }

    private static func glyphWidth(_ rows: [String]) -> Int {
        rows.first?.count ?? spaceWidth
    }

    static func glyph(for character: Character) -> [String] {
        if character == " " { return Array(repeating: String(repeating: ".", count: spaceWidth), count: glyphHeight) }
        if let rows = glyphs[character] { return rows }
        if let alias = aliases[character], let rows = glyphs[alias] { return rows }
        return glyphs["□"]!
    }

    /// Cyrillic letters that share their shape with Latin ones.
    private static let aliases: [Character: Character] = [
        "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H",
        "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X",
        "–": "-", "—": "—", "×": "X", "’": "'", "‘": "'", "“": "\"", "”": "\"", "«": "\"", "»": "\""
    ]

    private static let glyphs: [Character: [String]] = [
        // MARK: Latin
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],

        // MARK: Cyrillic (letters not aliased to Latin)
        "Б": ["#####", "#....", "#....", "####.", "#...#", "#...#", "####."],
        "Г": ["#####", "#....", "#....", "#....", "#....", "#....", "#...."],
        "Д": ["..##.", ".#.#.", ".#.#.", ".#.#.", ".#.#.", "#####", "#...#"],
        "Ё": [".#.#.", ".....", "#####", "#....", "####.", "#....", "#####"],
        "Ж": ["#.#.#", "#.#.#", ".###.", "..#..", ".###.", "#.#.#", "#.#.#"],
        "З": [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],
        "И": ["#...#", "#...#", "#..##", "#.#.#", "##..#", "#...#", "#...#"],
        "Й": [".#.#.", "..#..", "#...#", "#..##", "#.#.#", "##..#", "#...#"],
        "Л": ["..###", ".#..#", ".#..#", ".#..#", ".#..#", ".#..#", "#...#"],
        "П": ["#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#"],
        "У": ["#...#", "#...#", "#...#", ".####", "....#", "#...#", ".###."],
        "Ф": ["..#..", ".###.", "#.#.#", "#.#.#", "#.#.#", ".###.", "..#.."],
        "Ц": ["#..#.", "#..#.", "#..#.", "#..#.", "#..#.", "#####", "....#"],
        "Ч": ["#...#", "#...#", "#...#", ".####", "....#", "....#", "....#"],
        "Ш": ["#.#.#", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#####"],
        "Щ": ["#.#.#.", "#.#.#.", "#.#.#.", "#.#.#.", "#.#.#.", "######", ".....#"],
        "Ъ": ["##...", ".#...", ".#...", ".###.", ".#..#", ".#..#", ".###."],
        "Ы": ["#...#", "#...#", "#...#", "##..#", "#.#.#", "#.#.#", "##..#"],
        "Ь": ["#....", "#....", "#....", "####.", "#...#", "#...#", "####."],
        "Э": [".###.", "#...#", "....#", ".####", "....#", "#...#", ".###."],
        "Ю": ["#..#.", "#.#.#", "#.#.#", "###.#", "#.#.#", "#.#.#", "#..#."],
        "Я": [".####", "#...#", "#...#", ".####", "..#.#", ".#..#", "#...#"],

        // MARK: Digits
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],

        // MARK: Punctuation
        ".": [".", ".", ".", ".", ".", ".", "#"],
        ",": ["..", "..", "..", "..", "..", ".#", "#."],
        ":": [".", "#", ".", ".", ".", "#", "."],
        ";": ["..", ".#", "..", "..", "..", ".#", "#."],
        "!": ["#", "#", "#", "#", "#", ".", "#"],
        "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
        "'": ["#", "#", ".", ".", ".", ".", "."],
        "\"": ["#.#", "#.#", "...", "...", "...", "...", "..."],
        "-": ["....", "....", "....", "####", "....", "....", "...."],
        "—": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
        "_": [".....", ".....", ".....", ".....", ".....", ".....", "#####"],
        "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
        "=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
        "*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
        "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
        "(": ["..#", ".#.", "#..", "#..", "#..", ".#.", "..#"],
        ")": ["#..", ".#.", "..#", "..#", "..#", ".#.", "#.."],
        "[": ["###", "#..", "#..", "#..", "#..", "#..", "###"],
        "]": ["###", "..#", "..#", "..#", "..#", "..#", "###"],
        "<": ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"],
        ">": ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."],
        "&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
        "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
        "%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
        "©": [".###.", "#...#", "#.###", "#.#.#", "#.###", "#...#", ".###."],

        // MARK: Symbols / icons
        "♥": [".....", ".#.#.", "#####", "#####", ".###.", "..#..", "....."],
        "▶": ["#....", "##...", "###..", "####.", "###..", "##...", "#...."],
        "◀": ["....#", "...##", "..###", ".####", "..###", "...##", "....#"],
        "■": [".....", "#####", "#####", "#####", "#####", "#####", "....."],
        "⏸": ["##.##", "##.##", "##.##", "##.##", "##.##", "##.##", "##.##"],
        "⏏": ["..#..", ".###.", "#####", ".....", "#####", "#####", "....."],
        "●": [".....", ".###.", "#####", "#####", "#####", ".###.", "....."],
        "□": ["#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#####"]
    ]
}

/// The text as a shape made of square pixels — fill it with any style.
struct PixelTextShape: Shape {
    let text: String
    let pixel: CGFloat
    var bold = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for cell in PixelFont.cells(for: text, bold: bold) {
            path.addRect(CGRect(
                x: rect.minX + CGFloat(cell.x) * pixel,
                y: rect.minY + CGFloat(cell.y) * pixel,
                width: pixel,
                height: pixel
            ))
        }
        return path
    }
}

/// Pixel-font text view. Its size comes from the font grid, so layout stays exact.
/// Uses the current foreground style (colors, gradients).
struct PixelText: View {
    let text: String
    /// Size of one font pixel in points (snapped to the device pixel grid).
    var pixel: CGFloat = 2
    var bold = false

    @Environment(\.displayScale) private var displayScale

    init(_ text: String, pixel: CGFloat = 2, bold: Bool = false) {
        self.text = text
        self.pixel = pixel
        self.bold = bold
    }

    var body: some View {
        let size = PixelText.snapped(pixel, scale: displayScale)
        PixelTextShape(text: text, pixel: size, bold: bold)
            .frame(
                width: CGFloat(PixelFont.width(of: text, bold: bold)) * size,
                height: CGFloat(PixelFont.glyphHeight) * size
            )
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    /// Rounds a pixel size to whole device pixels so edges stay razor-sharp.
    static func snapped(_ pixel: CGFloat, scale: CGFloat) -> CGFloat {
        max((pixel * scale).rounded(), 1) / scale
    }

    /// Like `snapped`, but never larger than `pixel` — use for layout units that must fit.
    static func snappedDown(_ pixel: CGFloat, scale: CGFloat) -> CGFloat {
        max((pixel * scale).rounded(.down), 1) / scale
    }
}

extension View {
    /// Hard 1-pixel drop shadow, like text on old arcade / console screens.
    func pixelShadow(_ color: Color = .black.opacity(0.6), offset: CGFloat = 1) -> some View {
        shadow(color: color, radius: 0, x: offset, y: offset)
    }
}
