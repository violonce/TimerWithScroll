//
//  ViewController.swift
//  TimerWithScroll
//
//  Created by Илья on 02.11.2026.
//

import UIKit

class TimerScrollBugViewController2: UIViewController {

    // MARK: - UI
    private let scrollView    = UIScrollView()
    private let stackView     = UIStackView()
    private let brokenLabel   = UILabel()
    private let fixedLabel    = UILabel()
    private let dispatchLabel = UILabel()
    private let asyncLabel    = UILabel()

    // MARK: - State
    private var brokenTimer:   Timer?
    private var fixedTimer:    Timer?
    private var dispatchTimer: DispatchSourceTimer?
    private var asyncTask:     Task<Void, Never>?

    private var brokenCount   = 0
    private var fixedCount    = 0
    private var dispatchCount = 0
    private var asyncCount    = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Timer + ScrollView Bug"
        view.backgroundColor = .systemBackground
        setupUI()
        startTimers()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        brokenTimer?.invalidate()
        fixedTimer?.invalidate()
        dispatchTimer?.cancel()
        asyncTask?.cancel()     // cooperative cancellation propagates into the for-await loop
    }

    // MARK: - Timers

    private func startTimers() {

        // ❌ BROKEN — .default mode only, pauses during scroll
        brokenTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.brokenCount += 1
            self.brokenLabel.text = "Ticks: \(self.brokenCount)"
        }

        // ✅ FIXED — .common covers both .default and .tracking
        fixedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.fixedCount += 1
            self.fixedLabel.text = "Ticks: \(self.fixedCount)"
        }
        RunLoop.main.add(fixedTimer!, forMode: .common)

        // 🚀 DISPATCH — kernel-level, no run loop needed
        let source = DispatchSource.makeTimerSource(queue: .global())
        source.schedule(deadline: .now(), repeating: .milliseconds(100))
        source.setEventHandler { [weak self] in
            guard self != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dispatchCount += 1
                self.dispatchLabel.text = "Ticks: \(self.dispatchCount)"
            }
        }
        source.resume()
        dispatchTimer = source

        // ⚡️ ASYNC — Swift concurrency, Task + AsyncStream
        asyncTask = startAsyncTimer()
    }

    // Returned so we can store it in asyncTask and cancel later
    @discardableResult
    private func startAsyncTimer() -> Task<Void, Never> {
        // Task { } inherits the actor context of its call site.
        // Since startTimers() is called from viewDidLoad() on the main actor,
        // this Task runs on the MainActor — no DispatchQueue.main.async needed.
        Task { @MainActor in
            for await _ in Self.makeTicker(interval: .milliseconds(100)) {
                // Already on MainActor — safe to touch UI directly
                asyncCount += 1
                asyncLabel.text = "Ticks: \(asyncCount)"
            }
            // Loop exits when the Task is cancelled (asyncTask?.cancel())
        }
    }

    /// An AsyncStream that emits Void every `interval`.
    /// The continuation's onTermination cancels the inner DispatchSourceTimer
    /// when the stream is deallocated or the consuming Task is cancelled.
    private static func makeTicker(interval: DispatchTimeInterval) -> AsyncStream<Void> {
            AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let source = DispatchSource.makeTimerSource(queue: .global())
            source.schedule(deadline: .now(), repeating: interval)
            source.setEventHandler {
                continuation.yield()    // push a tick into the stream
            }
            source.resume()

            // Called when the Task is cancelled or the stream is deallocated
            continuation.onTermination = { _ in
                source.cancel()
            }
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        stackView.addArrangedSubview(makeCard(
            title: "❌ Broken Timer",
            subtitle: "scheduledTimer — .default mode only",
            explanation: "Pauses during scroll because the run loop switches to .tracking mode.",
            countLabel: brokenLabel,
            color: .systemRed
        ))
        stackView.addArrangedSubview(makeCard(
            title: "✅ Fixed Timer",
            subtitle: "scheduledTimer + RunLoop.main.add(forMode: .common)",
            explanation: "Keeps ticking during scroll — .common covers both .default and .tracking modes.",
            countLabel: fixedLabel,
            color: .systemGreen
        ))
        stackView.addArrangedSubview(makeCard(
            title: "🚀 DispatchSource Timer",
            subtitle: "DispatchSource.makeTimerSource(queue: .global())",
            explanation: "Kernel-level timer, no run loop involved. Fires on background thread, UI update dispatched to main.",
            countLabel: dispatchLabel,
            color: .systemBlue
        ))
        stackView.addArrangedSubview(makeCard(
            title: "⚡️ Async Timer",
            subtitle: "Task { @MainActor } + AsyncStream",
            explanation: "Modern Swift concurrency. AsyncStream wraps a DispatchSourceTimer and yields ticks. Task cancellation automatically tears down the stream via onTermination.",
            countLabel: asyncLabel,
            color: .systemPurple
        ))

        for i in 1...10 {
            stackView.addArrangedSubview(makeFillerRow(index: i))
        }
    }

    private func makeCard(
        title: String,
        subtitle: String,
        explanation: String,
        countLabel: UILabel,
        color: UIColor
    ) -> UIView {
        let card = UIView()
        card.backgroundColor = color.withAlphaComponent(0.08)
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1.5
        card.layer.borderColor = color.withAlphaComponent(0.3).cgColor

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let explanationLabel = UILabel()
        explanationLabel.text = explanation
        explanationLabel.font = .systemFont(ofSize: 13)
        explanationLabel.textColor = .secondaryLabel
        explanationLabel.numberOfLines = 0

        countLabel.text = "Ticks: 0"
        countLabel.font = .monospacedSystemFont(ofSize: 36, weight: .bold)
        countLabel.textColor = color
        countLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, subtitleLabel, countLabel, explanationLabel
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func makeFillerRow(index: Int) -> UIView {
        let row = UIView()
        row.backgroundColor = .secondarySystemBackground
        row.layer.cornerRadius = 12

        let label = UILabel()
        label.text = "Scroll to see the difference  (\(index)/10)"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 20),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -20),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
        ])
        return row
    }
}
//```
//
//## How the async version works end to end
//```
//asyncTask?.cancel()
//      │
//      ▼
//Task is cancelled
//      │
//      ▼
//for-await loop checks cancellation, exits
//      │
//      ▼
//AsyncStream is deallocated
//      │
//      ▼
//continuation.onTermination fires
//      │
//      ▼
//source.cancel() — DispatchSourceTimer torn down

