//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A type that handles timer callbacks scheduled with ``EventLoop/setTimer(for:_:)-5e37g``.
///
/// - Seealso: ``EventLoop/setTimer(for:_:)-5e37g``.
public protocol NIOTimerHandler {
    func timerFired(loop: any EventLoop)
}

/// An opaque handle that can be used to cancel a timer.
///
/// Users cannot create an instance of this type; it is returned by ``EventLoop/setTimer(for:_:)-5e37g``.
///
/// - Seealso: ``EventLoop/setTimer(for:_:)-5e37g``.
public struct NIOTimer {
    @usableFromInline
    enum Backing {
        /// A task created using `EventLoop.scheduleTask(deadline:_:)`, used by default for `EventLoop` implementations.
        case scheduledTask(Scheduled<Void>)
        /// An identifier for a timer, used by `EventLoop` implementations that conform to `CustomTimerImplementation`.
        case custom(eventLoop: any NIOCustomTimerImplementation, id: UInt64)
    }

    @usableFromInline
    var backing: Backing

    fileprivate init(_ scheduled: Scheduled<Void>) {
        self.backing = .scheduledTask(scheduled)
    }

    @inlinable
    init(_ eventLoop: any NIOCustomTimerImplementation, id: UInt64) {
        self.backing = .custom(eventLoop: eventLoop, id: id)
    }

    /// Cancel the timer associated with this handle.
    @inlinable
    public func cancel() {
        switch self.backing {
        case .scheduledTask(let scheduled):
            scheduled.cancel()
        case .custom(let eventLoop, let id):
            eventLoop.cancelTimer(id)
        }
    }
}

/// Default implementation of `setSimpleTimer(for deadline:_:)`, backed by `EventLoop.scheduleTask`.
extension EventLoop {
    @discardableResult
    public func setTimer(for deadline: NIODeadline, _ handler: any NIOTimerHandler) -> NIOTimer {
        NIOTimer(self.scheduleTask(deadline: deadline) { handler.timerFired(loop: self) })
    }
}

/// Default implementation of `setSimpleTimer(for duration:_:)`, delegating to `setSimpleTimer(for deadline:_:)`.
extension EventLoop {
    @discardableResult
    @inlinable
    public func setTimer(for duration: TimeAmount, _ handler: any NIOTimerHandler) -> NIOTimer {
        self.setTimer(for: .now() + duration, handler)
    }
}

/// Extension point for `EventLoop` implementations implement a custom timer.
public protocol NIOCustomTimerImplementation: EventLoop {
    /// Set a timer that calls handler at the given time.
    ///
    /// Implementations must return an integer identifier that uniquely identifies the timer.
    func setTimer(for deadline: NIODeadline, _ handler: any NIOTimerHandler) -> UInt64

    /// Cancel a timer with a given timer identifier.
    func cancelTimer(_ id: UInt64)
}

/// Default implementation of `setSimpleTimer(for deadline:_:)` for `EventLoop` types that opted in to `CustomeTimerImplementation`.
extension EventLoop where Self: NIOCustomTimerImplementation {
    @inlinable
    public func setTimer(for deadline: NIODeadline, _ handler: any NIOTimerHandler) -> NIOTimer {
        NIOTimer(self, id: self.setTimer(for: deadline, handler))
    }
}
