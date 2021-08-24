//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import XCTest
import NIOCore
import NIOEmbedded
@testable import _NIOConcurrency

#if compiler(>=5.5)

/// This test exists here to try and repro an issue in in another project. As a result some of the types look bizarre.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
class AsyncAwaitHelpersTests: XCTestCase {

    class Context {
        let eventLoop: EventLoop
        let somePromise: EventLoopPromise<String>
        init(eventLoop: EventLoop) {
            self.eventLoop = eventLoop
            self.somePromise = eventLoop.makePromise()
        }
    }

    class Handler {
        struct HandlerError: Error {}

        let context: Context
        let eventLoop: EventLoop
        var task: Task<Void, Never>? = nil

        init(eventLoop: EventLoop) {
            self.eventLoop = eventLoop
            self.context = Context(eventLoop: self.eventLoop)
            context.somePromise.futureResult.whenComplete(self.completionHandler(_:))
            self.task = context.somePromise.completeWithTask {
                try await Task.sleep(nanoseconds: 200)
                guard !Task.isCancelled else {
                    throw CancellationError()
                }
                return "OK"
            }
        }

        func mockError() {
            let error = HandlerError()
            log("calling handleError(_:) with error: \(error)")
            self.handleError(error)
        }

        func completionHandler(_ result: Result<String, Error>) {
            switch result {
            case .success(let value):
                log("was success with value: \(value)")
            case .failure(let error):
                log("was failure with error: \(error)")
                handleError(error)
            }
        }

        func handleError(_ error: Error) {
            if let task = self.task {
                log("canceling task")
                task.cancel()
            }
            log("failing promise with error: \(error)")
            context.somePromise.fail(error)
        }
    }

    func testPromiseCompletedWithSuccessfulTaskInClassAsyncWithAwaitWithYield() { XCTAsyncTest {
        let iterations = 1_000_000
        for iteration in 1...iterations {
            print("---")
            print("Starting test iteration \(iteration)")
            let group = EmbeddedEventLoop()
            let loop = group.next()

            let h = Handler(eventLoop: loop)
            try await Task.sleep(nanoseconds: 1000)
            h.mockError()
            try await Task.sleep(nanoseconds: 1000)

            XCTAssertNotNil(h.task)
            await h.task?.value
        }
    } }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
fileprivate extension XCTestCase {
  /// Cross-platform XCTest support for async-await tests.
  ///
  /// Currently the Linux implementation of XCTest doesn't have async-await support.
  /// Until it does, we make use of this shim which uses a detached `Task` along with
  /// `XCTest.wait(for:timeout:)` to wrap the operation.
  ///
  /// - NOTE: Support for Linux is tracked by https://bugs.swift.org/browse/SR-14403.
  /// - NOTE: Implementation currently in progress: https://github.com/apple/swift-corelibs-xctest/pull/326
  func XCTAsyncTest(
    expectationDescription: String = "Async operation",
    timeout: TimeInterval = 30,
    file: StaticString = #file,
    line: Int = #line,
    operation: @escaping () async throws -> Void
  ) {
    let expectation = self.expectation(description: expectationDescription)
    Task {
      do {
        try await operation()
      } catch {
        XCTFail("Error thrown while executing async function @ \(file):\(line): \(error)")
        Thread.callStackSymbols.forEach { print($0) }
      }
      expectation.fulfill()
    }
    self.wait(for: [expectation], timeout: timeout)
  }
}

@inline(__always)
fileprivate func log(_ message: String, function: String = #function, line: Int = #line, file: String = #fileID) {
    #if os(macOS)
    // The thread numbers printed by LLDB (and visible in the Xcode debugger are 1-based).
    let threadNumber = "\(Thread.current.value(forKeyPath: "_seqNum") as! Int + 1)"
    #else
    let threadNumber = "unknown"
    #endif
    print("on thread \(threadNumber) in \(function): \(message)")
}

#endif
