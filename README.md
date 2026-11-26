# Runner shutdown during a composite action ends the job `cancelled`

When a self-hosted runner receives a shutdown signal (SIGTERM: a node shutdown, a pod eviction, a spot reclaim) while a job runs, the job should end **failed**, as it does since [actions/runner#1792](https://github.com/actions/runner/pull/1792). It ends **cancelled** instead when the stopped step is inside a composite action and the composite has another step after it.

A cancelled job looks the same as one a person cancelled, so tooling that reruns jobs lost to a runner shutdown cannot tell them apart.

## Result

[Run 45765619032](https://github.com/Akais24/runner-composite-shutdown-repro/actions/runs/45765619032) on `ubuntu-latest`, runner 2.338.2. Each job sends SIGTERM to `Runner.Listener` 15 s into a `sleep 300` step ([stop-runner.sh](.github/stop-runner.sh)).

| Job | Where the step that gets stopped runs | Job conclusion |
| --- | --- | --- |
| `plain-step` | a plain `run` step | failure |
| `composite-last-step` | the last step of a composite action | failure |
| `composite-step-with-next-step` | a composite step with another step after it | **cancelled** |

All three logs show `The runner has received a shutdown signal` and then `The operation was canceled.` In the third job, the composite's next step is skipped:

```
##[end-action id=__self.__run;outcome=cancelled;conclusion=cancelled;duration_ms=27587]
##[start-action display=Run echo "next step";id=__self.__run_2]
##[end-action id=__self.__run_2;outcome=skipped;conclusion=skipped;duration_ms=0]
```

## Cause

`StepsRunner` sets the job result from the runner shutdown token since #1792 ([StepsRunner.cs#L152-L154](https://github.com/actions/runner/blob/aea9aaa3a0b49933412c6f59d7f05be037207a28/src/Runner.Worker/StepsRunner.cs#L152-L154), [#L193-L195](https://github.com/actions/runner/blob/aea9aaa3a0b49933412c6f59d7f05be037207a28/src/Runner.Worker/StepsRunner.cs#L193-L195)):

```csharp
jobContext.Result = HostContext.RunnerShutdownToken.IsCancellationRequested
                    ? TaskResult.Failed
                    : TaskResult.Canceled;
```

`CompositeActionHandler` sets `Canceled` unconditionally in the same two places:

- the job cancellation callback registered for each composite step ([CompositeActionHandler.cs#L338-L343](https://github.com/actions/runner/blob/aea9aaa3a0b49933412c6f59d7f05be037207a28/src/Runner.Worker/Handlers/CompositeActionHandler.cs#L338-L343));
- the branch for a composite step that starts after the job token was already cancelled ([CompositeActionHandler.cs#L376-L383](https://github.com/actions/runner/blob/aea9aaa3a0b49933412c6f59d7f05be037207a28/src/Runner.Worker/Handlers/CompositeActionHandler.cs#L376-L383)).

With one composite step, the outer `StepsRunner` callback still writes `Failed` afterwards. With a step after it, the second place runs last and overwrites the result with `Canceled`, which is what the third job shows.

A fix would apply the same `RunnerShutdownToken` check in both places of `CompositeActionHandler`.

## Reproduce

Fork this repository and run the `repro` workflow (`workflow_dispatch`), or push to `main`. It needs only GitHub-hosted runners.
