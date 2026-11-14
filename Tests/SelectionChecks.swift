import Foundation

/// The rules for what counts as a selection. Never posts Cmd+C or touches the clipboard.
@main
struct SelectionChecks {
    static func main() {
        precondition(SelectionReader.isSelectedText("hello"))
        precondition(SelectionReader.isSelectedText("first line\nsecond line\n"))
        precondition(SelectionReader.isSelectedText("first line\r\nsecond line"))
        precondition(SelectionReader.isSelectedText("a selected line without its newline"))
        precondition(!SelectionReader.isSelectedText(""))
        precondition(!SelectionReader.isSelectedText("\n"))
        precondition(!SelectionReader.isSelectedText("  \t\n"))
        precondition(!SelectionReader.isSelectedText("let x = 1\n"), "editor line copy")
        precondition(!SelectionReader.isSelectedText("let x = 1\r\n"), "editor line copy with CRLF")
        print("Selection checks passed")
    }
}
