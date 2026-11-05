#!/usr/bin/env bash
# Snapshot a finished training run into this repo, so it is versioned with git:
#   policy/        policy.onnx (+ .data), the last model_<N>.pt, deploy.yaml used to deploy it
#   training/      params/env.yaml + params/agent.yaml (the EXACT configuration of the run),
#                  RUN.md (which run, checkpoint, sizes) and VERSIONS.md (software + GPU)
#
#   bash scripts/import_run.sh <run dir> [path to unitree_rl_mjlab]
#   e.g. bash scripts/import_run.sh ~/g1_ws/unitree_rl_mjlab/logs/rsl_rl/g1_23dof_velocity/2026-10-20_14-05-09
# unitree_rl_mjlab path: 2nd argument, else $UNITREE_RL_MJLAB, else ~/g1_ws/unitree_rl_mjlab.
# Then: git add -A && git commit -m "Import walking run <name>"
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$(cd "${1:?usage: import_run.sh <run dir> [unitree_rl_mjlab dir]}" && pwd)"
URL="${2:-${UNITREE_RL_MJLAB:-$HOME/g1_ws/unitree_rl_mjlab}}"
SDK="${UNITREE_SDK2:-$HOME/g1_ws/unitree_sdk2}"

[ -f "$RUN/params/env.yaml" ] || { echo "No params/env.yaml in $RUN: not a training run folder"; exit 1; }
LAST="$(ls "$RUN"/model_*.pt 2>/dev/null | sort -V | tail -n 1 || true)"
[ -n "$LAST" ] || { echo "No model_*.pt in $RUN"; exit 1; }

mkdir -p "$REPO/policy" "$REPO/training/params"
cp "$RUN/params/env.yaml" "$RUN/params/agent.yaml" "$REPO/training/params/"
# Privacy: no local paths (user name, folder names) in published files.
URL_ABS="$(cd "$URL" 2>/dev/null && pwd || echo "$URL")"
sed -i -e "s#$URL_ABS#<unitree_rl_mjlab>#g" -e "s#$HOME#~#g" \
  "$REPO/training/params/env.yaml" "$REPO/training/params/agent.yaml"
if grep -n -E "/home/|~/" "$REPO/training/params/"*.yaml; then
  echo "WARNING: the lines above still contain local paths: check them before publishing"
fi
rm -f "$REPO"/policy/model_*.pt
cp "$LAST" "$REPO/policy/"
if [ -f "$RUN/policy.onnx" ]; then
  cp "$RUN/policy.onnx" "$REPO/policy/"
  [ -f "$RUN/policy.onnx.data" ] && cp "$RUN/policy.onnx.data" "$REPO/policy/"
else
  echo "WARNING: no policy.onnx in $RUN (it is written at every checkpoint save)"
fi
DEPLOY="$URL/deploy/robots/g1_23dof/config/policy/velocity/v0/params/deploy.yaml"
DEPLOY_ORIG="$DEPLOY.orig"                       # the untouched one, if apply.sh made a backup
if [ -f "$DEPLOY_ORIG" ]; then cp "$DEPLOY_ORIG" "$REPO/policy/deploy.yaml"
elif [ -f "$DEPLOY" ]; then cp "$DEPLOY" "$REPO/policy/deploy.yaml"; fi

# Python of the training environment (for the versions), else the system one.
PY="python3"
[ -x "$URL/.venv/bin/python" ] && PY="$URL/.venv/bin/python"

sizes="$(cd "$REPO/policy" && ls -l --block-size=K policy.onnx* model_*.pt 2>/dev/null | awk '{print "- `" $9 "`: " $5}')"
summary="$("$PY" - "$REPO/training/params/env.yaml" "$REPO/training/params/agent.yaml" <<'EOF' 2>/dev/null || true
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
def load(p):
    try:
        return yaml.unsafe_load(open(p))
    except Exception:
        return None
env, agent = load(sys.argv[1]), load(sys.argv[2])
def get(d, *keys):
    for k in keys:
        if not isinstance(d, dict) or k not in d:
            return "?"
        d = d[k]
    return d
print("- envs in parallel: %s" % get(env, "scene", "num_envs"))
print("- steps per env per iteration: %s" % get(agent, "num_steps_per_env"))
print("- max iterations (config): %s" % get(agent, "max_iterations"))
print("- seed: %s" % get(agent, "seed"))
EOF
)"

cat > "$REPO/training/RUN.md" <<EOF
# Imported training run

- run folder: \`$(basename "$(dirname "$RUN")")/$(basename "$RUN")\`
- last checkpoint: \`$(basename "$LAST")\`
- imported: $(date -I)
${summary}

Files in \`policy/\`:
${sizes}

Exact configuration of the run: \`training/params/env.yaml\` and \`training/params/agent.yaml\`
(written by mjlab when the run started). Software versions: \`training/VERSIONS.md\`.
EOF

pkg_versions="$("$PY" - <<'EOF' 2>/dev/null || true
import importlib.metadata as m
for name in ("mjlab", "mujoco", "mujoco-warp", "warp-lang", "torch", "rsl-rl-lib", "onnx", "onnxruntime"):
    try:
        print("- %s %s" % (name, m.version(name)))
    except m.PackageNotFoundError:
        pass
EOF
)"
gitrev() { git -C "$1" rev-parse --short HEAD 2>/dev/null || echo "not a git checkout"; }
{
  echo "# Software and hardware of the run"
  echo
  echo "- OS: $( (lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2) | tr -d '"')"
  echo "- GPU: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo 'nvidia-smi not found')"
  echo "- Python (training env): $("$PY" -c 'import sys; print(sys.version.split()[0])' 2>/dev/null)"
  echo "- unitree_rl_mjlab: $(gitrev "$URL")"
  echo "- unitree_sdk2: $(gitrev "$SDK")"
  [ -n "$pkg_versions" ] && echo "$pkg_versions"
  echo
  echo "Recorded by scripts/import_run.sh on $(date -I)."
} > "$REPO/training/VERSIONS.md"

echo "Imported $(basename "$RUN") ($(basename "$LAST")) into $REPO"
echo "Next:  cd $REPO && git add -A && git commit -m \"Import walking run $(basename "$RUN")\""
