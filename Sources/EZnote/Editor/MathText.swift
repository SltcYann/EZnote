import Foundation

/// Convertit du LaTeX simple en texte Unicode lisible et modifiable :
/// `$\frac{a}{b} + x^2 \leq \sqrt{n}$` → « a⁄b + x² ≤ √n ».
enum MathText {
    private static let symbols: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ",
        "sigma": "σ", "tau": "τ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ",
        "Psi": "Ψ", "Omega": "Ω",
        "infty": "∞", "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈",
        "equiv": "≡", "sim": "∼", "propto": "∝", "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓",
        "to": "→", "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒", "Leftarrow": "⇐",
        "Leftrightarrow": "⇔", "iff": "⇔", "implies": "⇒", "mapsto": "↦",
        "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "cup": "∪", "cap": "∩",
        "forall": "∀", "exists": "∃", "emptyset": "∅", "varnothing": "∅", "neg": "¬", "land": "∧", "lor": "∨",
        "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "oint": "∮", "partial": "∂", "nabla": "∇",
        "degree": "°", "circ": "°", "ldots": "…", "cdots": "⋯", "dots": "…", "prime": "′", "angle": "∠",
        "perp": "⊥", "parallel": "∥", "quad": "  ", "qquad": "    ", ",": " ", ";": " ", "!": "",
        "sin": "sin", "cos": "cos", "tan": "tan", "ln": "ln", "log": "log", "exp": "exp", "lim": "lim",
        "min": "min", "max": "max", "det": "det",
    ]
    private static let blackboard: [String: String] = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ"]

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ",
        "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "o": "ᵒ",
        "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
        "T": "ᵀ", "*": "*", "′": "′",
    ]
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
        "v": "ᵥ", "x": "ₓ",
    ]

    /// Remplace chaque `$…$` d'un texte par sa version Unicode.
    static func convertInline(_ text: String) -> String {
        guard text.contains("$") else { return text }
        var output = "", rest = Substring(text)
        while let start = rest.firstIndex(of: "$") {
            let afterStart = rest.index(after: start)
            guard let end = rest[afterStart...].firstIndex(of: "$"), end > afterStart else { break }
            let inner = String(rest[afterStart..<end])
            // Sans commande, exposant ni indice, ce n'est pas une formule (« 5 $ et 6 $ ») : on garde tel quel.
            guard inner.contains(where: { "\\^_".contains($0) }) else {
                output += rest[...start]
                rest = rest[afterStart...]
                continue
            }
            output += rest[..<start]
            output += convert(inner)
            rest = rest[rest.index(after: end)...]
        }
        return output + rest
    }

    static func convert(_ latex: String) -> String {
        var s = latex
        for wrapper in ["\\left", "\\right", "\\displaystyle", "\\mathrm", "\\text", "\\textbf", "\\mathbf", "\\operatorname"] {
            s = s.replacingOccurrences(of: wrapper, with: "")
        }
        // \mathbb{R} → ℝ
        s = replace(#"\\mathbb\{([A-Z])\}"#, in: s) { blackboard[$0[1]] ?? $0[1] }
        // \frac{a}{b} → a⁄b (ou (a)/(b) si c'est long), \sqrt{x} → √x
        for _ in 0..<4 {
            s = replace(#"\\frac\{([^{}]*)\}\{([^{}]*)\}"#, in: s) { group in
                let a = group[1], b = group[2]
                let simple = { (t: String) in t.count <= 3 && t.allSatisfy { $0.isLetter || $0.isNumber } }
                return simple(a) && simple(b) ? "\(a)⁄\(b)" : "(\(a))/(\(b))"
            }
            s = replace(#"\\sqrt\{([^{}]*)\}"#, in: s) { $0[1].count <= 2 ? "√\($0[1])" : "√(\($0[1]))" }
        }
        // Commandes : \alpha → α
        s = replace(#"\\([A-Za-z]+|[,;!])"#, in: s) { symbols[$0[1]] ?? $0[1] }
        // Exposants et indices
        s = replace(#"\^\{([^{}]*)\}|\^(.)"#, in: s) { group in
            let body = group[1].isEmpty ? group[2] : group[1]
            return map(body, superscripts) ?? "^(\(body))"
        }
        s = replace(#"_\{([^{}]*)\}|_(.)"#, in: s) { group in
            let body = group[1].isEmpty ? group[2] : group[1]
            return map(body, subscripts) ?? "_(\(body))"
        }
        return s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
    }

    private static func map(_ text: String, _ table: [Character: Character]) -> String? {
        var result = ""
        for character in text where character != " " {
            guard let mapped = table[character] else { return nil }
            result.append(mapped)
        }
        return result
    }

    private static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var output = "", last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { i -> String in
                let range = match.range(at: i)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            output += transform(groups)
            last = NSMaxRange(match.range)
        }
        return output + ns.substring(from: last)
    }
}
