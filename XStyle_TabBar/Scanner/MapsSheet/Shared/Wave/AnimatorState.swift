//
//  AnimationState.swift
//  Wave
//
//  Copyright (c) 2022 Janum Trivedi.
//
//  Adapted from Wave 0.3.3; modified (trimmed, Spring→WaveSpring, startTime fix). MIT — see THIRD_PARTY_NOTICES.md

/**
 The current state of an `Animation`.
 */
nonisolated enum AnimatorState {
    /**
     The animation is not currently running, but is ready.
     */
    case inactive

    /**
     The animation is currently active and executing.
     */
    case running

    /**
     The animation has just stopped, and will be reset to the `inactive` state.
     */
    case ended
}
