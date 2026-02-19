//
//  SentencePromptBuilder.swift
//  claudeBlast
//

import Foundation

struct SentencePromptBuilder {
    var ageGradeLevel: Int = 2
    var repetitionCount: Int = 0
    var conversationContext: [String] = []

    func buildSystemPrompt() -> String {
        var parts: [String] = []

        parts.append("""
        You are a speech assistant for a non-verbal child. \
        The child selects word tiles to communicate. \
        Your job is to turn the selected words into a natural, \
        age-appropriate sentence using the grammar of a \
        \(gradeDescription(ageGradeLevel)) student.
        """)

        parts.append("""
        Rules:
        - Output ONLY the sentence, no quotes, no explanation.
        - Keep it short and natural.
        - Use the words provided as the core meaning.
        - Make it sound like something a child would actually say.
        """)

        if repetitionCount > 0 {
            parts.append(escalationPrompt(repetitionCount))
        }

        return parts.joined(separator: "\n\n")
    }

    func formatUserPrompt(tiles: [TileSelection]) -> String {
        let tileDescriptions = tiles.map { "\($0.value) (\($0.wordClass))" }
        return tileDescriptions.joined(separator: ", ")
    }

    private func gradeDescription(_ grade: Int) -> String {
        switch grade {
        case 1: return "1st-grade"
        case 2: return "2nd-grade"
        case 3: return "3rd-grade"
        default: return "\(grade)th-grade"
        }
    }

    private func escalationPrompt(_ count: Int) -> String {
        switch count {
        case 1:
            return "The user has repeated this combination. They may want emphasis — make the sentence more direct."
        case 2:
            return "The user has repeated this combination twice. They are insistent — make the sentence urgent."
        default:
            return "The user has repeated this combination \(count) times. This is very important to them — escalate urgency strongly."
        }
    }
}
