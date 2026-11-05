# training/

Filled in by `scripts/import_run.sh <run dir>`:

- `params/env.yaml`, `params/agent.yaml`: the exact environment and PPO configuration of the
  run, as mjlab wrote them when the run started. Two runs with the same files (and the same
  software versions) are the same experiment.
- `RUN.md`: which run and checkpoint.
- `VERSIONS.md`: OS, GPU, driver and package versions.

`train.sh` is the command that produced the run.
