#!/usr/bin/env bash
# Train the G1-23DoF walking (velocity tracking) policy with Unitree's recipe in mjlab.
# Run from anywhere; the checkout path can be passed as the first argument.
#   bash training/train.sh [path to unitree_rl_mjlab] [num envs]
set -euo pipefail
URL="${1:-${UNITREE_RL_MJLAB:-$HOME/g1_ws/unitree_rl_mjlab}}"
ENVS="${2:-4096}"      # 4096 as in Unitree's README; lower it if the GPU runs out of memory
cd "$URL"
source .venv/bin/activate
python scripts/train.py Unitree-G1-23Dof-Flat --env.scene.num-envs="$ENVS"
# Results: logs/rsl_rl/g1_23dof_velocity/<date_time>/ (model_<N>.pt every 100 iterations,
# policy.onnx re-exported at every save, params/env.yaml + agent.yaml, TensorBoard events).
# Watch:   tensorboard --logdir logs/rsl_rl/g1_23dof_velocity
# Look:    python scripts/play.py Unitree-G1-23Dof-Flat --checkpoint_file=logs/rsl_rl/g1_23dof_velocity/<run>/model_<N>.pt
# Keep it: bash <this repo>/scripts/import_run.sh logs/rsl_rl/g1_23dof_velocity/<run>
