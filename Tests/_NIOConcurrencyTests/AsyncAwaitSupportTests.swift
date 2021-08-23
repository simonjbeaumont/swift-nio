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
    open class BaseContext {
        let eventLoop: EventLoop
        init(eventLoop: EventLoop) {
            self.eventLoop = eventLoop
        }
    }


    open class SomeContext: BaseContext {
        let somePromise: EventLoopPromise<String>
        override init(eventLoop: EventLoop) {
            self.somePromise = eventLoop.makePromise()
            super.init(eventLoop: eventLoop)
        }

    }

    final class _SomeContext: SomeContext {
        override init(eventLoop: EventLoop) {
            super.init(eventLoop: eventLoop)
        }
    }

    class Handler {
        enum HandlerError: Error {
            case new(String)
        }
        enum State {
            case initial
            case holdsContext(outerHandler: () -> Void, context: _SomeContext)
        }

        let eventLoop: EventLoop
        var state: State = .initial
        var task: Task<Void, Never>? = nil

        init(eventLoop: EventLoop) {
            self.eventLoop = eventLoop
        }

        func moveState() {
            let context = _SomeContext(eventLoop: self.eventLoop)
            self.state = .holdsContext(outerHandler: {
                print("in outer handler function")
            }, context: context)
            context.somePromise.futureResult.whenComplete(self.completionHandler(_:))
            self.task = context.somePromise.completeWithTask {
                await Task.sleep(200)
                guard !Task.isCancelled else {
                    throw CancellationError()
                }
                return "yay"
            }
        }

        func mockError() {
            self.handleError(HandlerError.new("FOO"))
        }

        func completionHandler(_ result: Result<String, Error>) {
            print("in completion handler for promise")
            switch result {
            case .success(let value):
                print("was success with value: \(value)")
            case .failure(let error):
                print("calling error handler with error: \(error)")
                handleError(error)
            }
        }

        func handleError(_ error: Error) {
            switch self.state {
            case .initial:
                print("in error handler: doing nothing")
            case .holdsContext(_, context: let context):
                print("in error handler: canceling task")
                self.task?.cancel()
                print("in error handler: failing promise")
                context.somePromise.fail(error)
            }

        }
    }

    func testPromiseCompletedWithSuccessfulTaskInClassAsyncWithAwaitWithYield() { XCTAsyncTest {
        print("Starting test \(UUID().uuidString)")
        let group = EmbeddedEventLoop()
        let loop = group.next()

        let h = Handler(eventLoop: loop)
        h.moveState()
        await Task.sleep(100)
        h.mockError()
        await Task.sleep(100)

        XCTAssertNotNil(h.task)
        await h.task!.value
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
    timeout: TimeInterval = 3,
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

#endif
