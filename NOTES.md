# Interview talking points: bluegreen-deploy
1. **Why reload, not restart.** `nginx -s reload` starts new workers with the new config while old workers finish their in-flight requests. That's why 501 requests saw 0 errors across the switch.
2. **Two gates.** The pre-switch check runs on the idle color directly, so a bad build never gets traffic. The post-switch smoke test runs through the LB and catches config or routing mistakes. Both roll back automatically.
3. **Version check, not just 200.** The health check confirms `version == expected`. A stale container answering 200 would otherwise pass.
4. **The bug story.** An orphaned process held the port, so a good release failed its health check. The lesson: a rollback system also needs reliable teardown. I fixed the PID capture and added a "wait for port free" loop.
5. **Atomic config swap.** Write to `.new`, `mv` it into place, run `nginx -t`, then reload. A bad config never gets loaded.
6. **Trade-offs vs canary/rolling.** Blue-green needs 2× capacity briefly but gives instant rollback. Canary limits blast radius using metrics. Rolling deploys are cheap but mix versions.
7. **DB caveat.** Both colors share a DB, so migrations must be expand/contract.
