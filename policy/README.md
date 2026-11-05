# policy/

The walking policy that is deployed, filled in by `scripts/import_run.sh`:

| File | What |
| --- | --- |
| `policy.onnx` (+ `policy.onnx.data` if present) | the actor network, exported by mjlab at every checkpoint save; this is what `g1_ctrl` runs |
| `model_<N>.pt` | the last checkpoint of the run (actor, critic, optimizer): to resume training or warm start new skills |
| `deploy.yaml` | how `g1_ctrl` builds the observations and actions for this policy (joint order, gains, scales) |

`sim2sim/apply.sh` copies `policy.onnx` and `deploy.yaml` into a `unitree_rl_mjlab` checkout.
