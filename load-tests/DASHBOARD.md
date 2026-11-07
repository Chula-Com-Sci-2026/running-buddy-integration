# Live k6 dashboard

The built-in k6 web dashboard displays load-test metrics during a run and exports a self-contained HTML report. A separate Grafana server is not required.

From `running-buddy-integration/`, once the test script is available:

```sh
./load-tests/scripts/run-dashboard.sh ./load-tests/k6/<script>.js
```

Replace `<script>` with the actual script name. Install k6 on the host first. Configure the gateway address, authentication, dataset, and workload as required by that script. The gateway must be reachable from the host; for Kubernetes, use the deployment's documented gateway access method.

The runner opens `http://127.0.0.1:5665` and saves `report.html` in a unique timestamped directory under `load-tests/results/`. It preserves k6's exit status, including threshold failures. Additional `k6 run` options can follow the script path.

Optional overrides:

```sh
K6_WEB_DASHBOARD_OPEN=false K6_WEB_DASHBOARD_PORT=5666 \
  ./load-tests/scripts/run-dashboard.sh ./load-tests/k6/<script>.js
```

Close the dashboard tab after the test if k6 remains running: k6 waits to exit while a dashboard browser connection remains open. By default, charts update every 10 seconds; exported reports require a test longer than three aggregation periods to include graphs.

This dashboard reports performance observed by k6. Pod CPU and memory require separate infrastructure monitoring. Inspect report contents before sharing because test metadata can contain application details.

Reference: [official k6 web dashboard documentation](https://grafana.com/docs/k6/latest/results-output/web-dashboard/).
