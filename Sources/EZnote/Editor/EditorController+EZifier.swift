import AppKit

/// EZifier : les notes (texte, transcription, photos, marque-pages) deviennent une leçon, écrite en direct.
extension EditorController {
    func ezify() {
        if isWorking { task?.cancel(); return }
        guard !isRecording else { errorMessage = "Arrête d'abord l'enregistrement du cours."; return }
        guard let textView, let storage else { return }
        let notes = NotesExporter.export(storage)
        guard !notes.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Écris d'abord quelques notes, puis appuie sur EZifier."
            return
        }
        let context = self.context
        let request = AIRequest(system: LessonPrompt.system,
                                user: LessonPrompt.userMessage(notes: notes.markdown, context: context),
                                images: notes.images)
        let events: AsyncThrowingStream<AIEvent, Error>
        do { events = try AI.stream(request) } catch { report(error); return }

        let original = NSAttributedString(attributedString: storage)
        author = AI.authorName
        textView.breakUndoCoalescing()
        textView.isEditable = false
        phase = .reading

        task = Task { [weak self] in
            var markdown = ""
            var lastRender = ContinuousClock.now
            do {
                for try await event in events {
                    guard let self else { return }
                    switch event {
                    case .searching:
                        self.phase = .searching
                    case .restart:
                        markdown = ""
                    case .text(let delta):
                        markdown += delta
                        self.phase = .writing
                        // Affichage en direct, ~15 fois par seconde : la leçon s'écrit sous les yeux.
                        if ContinuousClock.now - lastRender > .milliseconds(66) {
                            self.showLesson(markdown, attachments: notes.attachments)
                            lastRender = .now
                        }
                    }
                }
                guard let self else { return }
                guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.empty }
                self.showLesson(markdown, attachments: notes.attachments)
                let subject = LessonRenderer.extractSubject(markdown).subject
                if let subject, !subject.isEmpty, self.document?.info.subject.isEmpty == true {
                    self.document?.info.subject = subject
                }
                self.registerSwap(back: original, current: NSAttributedString(attributedString: storage))
                self.endWork()
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            } catch {
                guard let self else { return }
                self.replaceAll(with: original)
                self.endWork()
                self.report(error)
            }
        }
    }

    private func showLesson(_ markdown: String, attachments: [NSTextAttachment]) {
        let lesson = LessonRenderer.extractSubject(markdown).lesson
        replaceAll(with: LessonRenderer.render(lesson, author: author, images: attachments))
        textView?.scrollRangeToVisible(NSRange(location: storage?.length ?? 0, length: 0))
    }

    func endWork() {
        task = nil
        phase = .idle
        textView?.isEditable = true
        textView?.typingAttributes = LessonStyle.attributes(.body)
        if let textView { textView.window?.makeFirstResponder(textView) }
    }
}
