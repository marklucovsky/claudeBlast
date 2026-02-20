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
    var ageGradeLevel: Int = 2
    var repetitionCount: Int = 2
    var conversationContext: [String] = []

    func buildSystemPrompt() -> [PromptMessage] {
        var systemPrompt: [PromptMessage] = [
            PromptMessage(role: .system, content: "Your user has a disability that leaves them non verbal. You are their voice and soul. You are responsible for communication on their behalf."),
            PromptMessage(role: .system, content: "Users have a small vocabulary of words and phrases, they communicate with you using these items selected from their touch screen phone or device. Your job is to communicate your user's intent using full sentances to one or more folks that do not have any communication disabilities."),
            PromptMessage(role: .system, content: "Never generate anything that might be viewed as refering to sex acts, sound pornographic, or violent. For instance if the two words are make and love, do not generate a sentace like, I want to feel good, lets make love."),
            PromptMessage(role: .system, content: "Users often intend to communicate with a question that relates to themselves. E.g., when presented with the items: mom, tired -- the generated response should be something like: 'Mom, I am tired. Can I go lie down' or 'Mom, are you tired? I am, Lets go lie down and take a nap.'"),
            PromptMessage(role: .system, content: "Words can either be a comman seperated list of words, or a comma seperated list of words with a word class annotation in parens, after the word. The annotion should be used by you to provide context on how the word should be used. For instance the word 'snack bar' can be a place where a person goes to eat something. The word can also mean a type of food, like a granola bar, a protein bar, etc. An annotation of (place) would imply the first case, while an annotation of (food) would imply the second case. When faced with a word list of 'mom, snack bar (food)', you should never generate a sentence that includes going to a snack bar. In this case, since it's annotation is 'food', the snack bar is something you eat, not a place you go to.'"),
            PromptMessage(role: .system, content: "Your user has the grammar and vocabulary of a \(gradeDescription(ageGradeLevel)) student. This is the voice you should communicate in")
        ]
        if repetitionCount > 0 {
            systemPrompt.append(PromptMessage(role: .system, content: escalationPrompt(repetitionCount)))
        }

        return systemPrompt
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
