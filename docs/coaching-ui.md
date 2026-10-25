# Coach keyboard and request status

The Coach composer owns its keyboard focus locally. Tapping the introductory title or surrounding introduction dismisses the keyboard without clearing or sending the draft. Starting a downward scroll dismisses it immediately. Send, single-workout/week proposal, retry, cancellation, connection settings, and saved-workout navigation clear composer focus as part of their explicit actions. The dismissal tap is limited to the introduction so it does not intercept composer or other controls.

While a request is running, the navigation toolbar shows an indeterminate spinner and the model’s actual request label, such as **Planning your week…**, with accessibility identifier `coach-loading-status`. The toolbar Cancel action remains available. This status does not claim progress percentages, model reasoning, or provider completion.

## Test-first evidence

Root observed the UI test `CoachFlowTests.testCoachTitleAndDownwardScrollDismissKeyboardWithoutSendingTheDraft` fail at 04:08:51 UTC on 25 October 2026, at [CoachFlowTests.swift:21](../Tests/UI/CoachFlowTests.swift): tapping **Your next move.** left the keyboard visible after the keyboard precondition passed. The test also checks downward-scroll dismissal, preserved draft text, and absence of a sent Coach request.

The focused native UI test passed at 04:14:23 UTC: title tap and a downward swipe on the identified outer conversation scroll view both dismissed the visible keyboard, preserved the unsent draft, and sent no request. An intermediate run passed title dismissal but targeted an ambiguous first scroll view; the test now identifies `coach-conversation` explicitly. Build warnings: none. Rendered in-flight loading-toolbar acceptance remains separate; no provider request was made for keyboard verification.
