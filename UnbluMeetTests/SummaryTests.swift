import Testing
import Foundation
@testable import UnbluMeet

private func line(_ speaker: String, _ text: String, at: TimeInterval) -> TranscriptLine {
    TranscriptLine(speaker: speaker, text: text, at: at)
}

@Test func transcriptReplacesAGrowingUtteranceRatherThanRepeatingIt() {
    // Recognition re-reports one utterance as it extends.
    let transcript = CallTranscript()
    transcript.append(speaker: "Anna", text: "we should ship", at: 100)
    transcript.append(speaker: "Anna", text: "we should ship without device wide capture", at: 101)
    let lines = transcript.lines(after: 0)
    #expect(lines.count == 1)
    #expect(lines[0].text == "we should ship without device wide capture")
}

@Test func aDifferentSpeakerStartsANewLine() {
    let transcript = CallTranscript()
    transcript.append(speaker: "Anna", text: "we should ship", at: 100)
    transcript.append(speaker: "Denis", text: "we should ship it today", at: 101)
    #expect(transcript.lines(after: 0).count == 2)
}

@Test func blankRecognitionIsIgnored() {
    let transcript = CallTranscript()
    transcript.append(speaker: "Anna", text: "   ", at: 100)
    #expect(transcript.isEmpty)
}

@Test func theCursorOnlyYieldsNewLines() {
    let transcript = CallTranscript()
    transcript.append(speaker: "A", text: "one two three", at: 100)
    transcript.append(speaker: "B", text: "four five six", at: 200)
    #expect(transcript.lines(after: 150).count == 1)
}

@Test func trimmingKeepsTheMostRecentWords() {
    let lines = (0 ..< 10).map { line("A", "word word word word word", at: TimeInterval($0)) }
    let trimmed = CallTranscript.trimmed(lines, toWords: 12)
    #expect(CallTranscript.wordCount(trimmed) <= 12)
    #expect(trimmed.last?.at == 9)
}

@Test func trimmingKeepsAtLeastOneLineEvenIfItIsTooLong() {
    // Better an oversized single line than an empty prompt.
    let lines = [line("A", String(repeating: "word ", count: 500), at: 1)]
    #expect(CallTranscript.trimmed(lines, toWords: 10).count == 1)
}

@Test func aFullWindowIsLeftAlone() {
    let lines = (0 ..< 3).map { line("A", "one two three", at: TimeInterval($0)) }
    #expect(CallTranscript.trimmed(lines, toWords: 100).count == 3)
}

@Test func transcriptFormatsWithSpeakerLabels() {
    // Attribution is what the model needs to assign an action to a person.
    let text = CallTranscript.format([line("Anna", "I will do it", at: 1),
                                      line("Denis", "thanks", at: 2)])
    #expect(text == "Anna: I will do it\nDenis: thanks")
}

@Test func restatedItemsAreTreatedAsDuplicates() {
    // The model re-words the same decision, so exact matching lets them through.
    let existing = ["Marek will draft the documentation by Wednesday evening"]
    #expect(SummaryService.isDuplicate("Marek will draft documentation by Wednesday evening.", of: existing))
    #expect(SummaryService.isDuplicate("MAREK WILL DRAFT THE DOCUMENTATION BY WEDNESDAY EVENING", of: existing))
}

@Test func genuinelyDifferentItemsAreKept() {
    let existing = ["Marek will draft the documentation by Wednesday evening"]
    #expect(!SummaryService.isDuplicate("Anna will fix the Android 14 capture bug", of: existing))
}

@Test func contextFreeFragmentsAreDropped() {
    // Observed in a real run: items like these lost the ticket they referred to.
    #expect(!SummaryService.isWorthKeeping("Update ticket by Friday"))
    #expect(!SummaryService.isWorthKeeping("Mention in release notes"))
    #expect(SummaryService.isWorthKeeping("Marek will mention PROJ-101 in the release notes"))
    #expect(SummaryService.isWorthKeeping("Move PROJ-101 to next sprint"))
}

@Test func theWindowStaysWellUnderTheMeasuredCeiling() {
    // ~3,100 words was the measured hard limit; the window must leave room
    // for instructions, known items and the generated output.
    #expect(SummaryService.windowWordLimit < 3_100 / 2)
}

@Test func refreshCadenceIsWithinTheRequestedRange() {
    #expect(SummaryService.interval >= 30 && SummaryService.interval <= 60)
}

@Test func copiedTextCarriesOverviewAndItems() {
    let text = SummaryPanel.plainText(overview: "Release planning.",
                                      items: ["Marek writes the docs", "Anna fixes capture"])
    #expect(text.contains("Release planning."))
    #expect(text.contains("• Marek writes the docs"))
}

@Test func copyingAnEmptySummaryYieldsNothingRatherThanBullets() {
    #expect(SummaryPanel.plainText(overview: "", items: []) == "")
}
