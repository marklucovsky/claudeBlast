// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentencePromptBuilder.swift
//  claudeBlast
//

import Foundation

struct PromptMessage: Codable {
  public var id: String? = UUID().uuidString
  var role: String
  var content: String
  
  init(role: MessageRole, content: String) {
    self.role = role.rawValue
    self.content = content
  }
}

public enum MessageRole: String, Codable {
    /// The role for the system that manages the chat interface.
    case system
    /// The role for the human user who initiates the chat.
    case user
    /// The role for the artificial assistant who responds to the user.
    case assistant
}

struct SentencePromptBuilder {
    /// US grade-level approximation. No default — callers must pass the
    /// active child's value (or `ChildProfileResolver.fallbackAgeGrade`)
    /// explicitly. Removing the default prevents silently falling back to
    /// 2nd-grade when a caller forgets to wire the resolver.
    var ageGradeLevel: Int
    var repetitionCount: Int = 0
    var conversationContext: [String] = []

    /// Reinforces the word-class annotation rule near the end of the system
    /// turn. A small model otherwise lets its prior for a word override a
    /// surprising category (e.g. "pony (food)" comes out as a pet, not food).
    /// Kept as a system-prompt enhancement rather than appended to the user
    /// prompt so the user turn stays pure tile content.
    static let categoryHonorRule =
        "The category in parentheses after a word is that word's intended meaning — honor it even when unusual."

    func buildSystemPrompt() -> [PromptMessage] {
        let grade = gradeDescription(ageGradeLevel)
        var systemPrompt: [PromptMessage] = Self.loadBaseMessages(grade: grade)
            .map { PromptMessage(role: .system, content: $0) }
        systemPrompt.append(PromptMessage(role: .system, content: Self.categoryHonorRule))
        if repetitionCount > 0 {
            systemPrompt.append(PromptMessage(role: .system, content: escalationPrompt(repetitionCount)))
        }

        return systemPrompt
    }

    /// The user turn: just the selected tiles as `word (class)`, comma-joined.
    /// Enhancements (the category-honor rule, escalation) live in the system
    /// prompt — see `buildSystemPrompt`.
    func formatUserPrompt(tiles: [TileSelection]) -> String {
        tiles.map { "\($0.value) (\($0.wordClass))" }
            .joined(separator: ", ")
    }

    private func gradeDescription(_ grade: Int) -> String {
        switch grade {
        case 1: return "1st-grade"
        case 2: return "2nd-grade"
        case 3: return "3rd-grade"
        default: return "\(grade)th-grade"
        }
    }

    private static func loadBaseMessages(grade: String) -> [String] {
        guard let url = Bundle.main.url(forResource: "sentence_prompt", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([String].self, from: data)
        else { return hardcodedFallback(grade: grade) }
        return messages.map { $0.replacingOccurrences(of: "{grade}", with: grade) }
    }

    private static func hardcodedFallback(grade: String) -> [String] {
        [
            "Your user has a disability that leaves them non verbal. You are their voice and soul. You are responsible for communication on their behalf.",
            "Users have a small vocabulary of words and phrases, they communicate with you using these items selected from their touch screen phone or device. Your job is to communicate your user's intent using full sentences to one or more folks that do not have any communication disabilities.",
            "Never generate anything that might be viewed as refering to sex acts, sound pornographic, or violent. For instance if the two words are make and love, do not generate a sentence like, I want to feel good, lets make love.",
            "Users often intend to communicate with a question that relates to themselves. E.g., when presented with the items: mom, tired -- the generated response should be something like: 'Mom, I am tired. Can I go lie down' or 'Mom, are you tired? I am, Lets go lie down and take a nap.'. It would be very rare for the response to be centered on someone else, like 'Mom are you tired?'",
            "Assume that most usage is self centered. For instance selection of: mom, milk should translate to 'Mom can I have some milk' and not 'Mom, you should drink some milk'",
            "Words can either be a comma seperated list of words, or a comma seperated list of words with a word class annotation in parens, after the word. The annotion should be used by you to provide context on how the word should be used. For instance the word 'snack bar' can be a place where a person goes to eat something. The word can also mean a type of food, like a granola bar, a protein bar, etc. An annotation of (place) would imply the first case, while an annotation of (food) would imply the second case. When faced with a word list of 'mom, snack bar (food)', you should never generate a sentence that includes going to a snack bar. In this case, since it's annotation is 'food', the snack bar is something you eat, not a place you go to.'",
            "Your user has the grammar and vocabulary of a \(grade) student. This is the voice you should communicate in"
        ]
    }

    /// Escalation directive for a repeated selection. Repetition is the child's
    /// volume knob — the same tiles tapped again means "I want this MORE."
    ///
    /// Design (rewritten after the eval harness showed the old prompt jumped one
    /// notch on the first repeat then flatlined or regressed):
    /// - **Cumulative.** Each rung must be strictly more insistent than the
    ///   model's own previous sentence (supplied as its most recent reply), never
    ///   calmer and never a restatement. This is the fix for flat ramps.
    /// - **Graduated by count.** A concrete intensity ladder the model climbs as
    ///   the repeat count rises, so there's always a hotter rung to reach.
    /// - **No fixed anchor.** The illustration uses a neutral want ("juice") that
    ///   isn't real vocabulary, so the model learns the trajectory shape without
    ///   anchoring its wording to a specific example (the old "mom, hungry"
    ///   few-shot caused that case to regress toward the example).
    private func escalationPrompt(_ count: Int) -> String {
        """
        The child just selected the SAME tiles again — repeat #\(count). Repetition is how a \
        non-verbal child turns up the volume: the want hasn't changed, but they mean it MORE. \
        Your own previous sentence for this want is your most recent reply above. Make THIS \
        sentence clearly more insistent than that one — never calmer, never the same wording, \
        escalate on every repeat while keeping the exact same want and staying age-appropriate.

        Climb this intensity ladder as the repeat count rises (you are at #\(count)):
        • 1 — add urgency and a please ("really", "right now").
        • 2 — drop the softeners, state a need ("I need …", "now").
        • 3 — very emphatic: CAPITALIZE the key word and end with an exclamation.
        • 4+ — maximal: ALL-CAPS key words and multiple exclamation marks, like a child on the \
        edge of tears who will not be ignored.

        Example trajectory for a generic want, "juice":
        "Can I please have some juice?" → "I really want juice right now." → \
        "I need JUICE now!" → "I WANT JUICE NOW!!!"
        Apply that escalation to the child's actual tiles — do not mention juice.
        """
    }
}
