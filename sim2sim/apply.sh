#!/usr/bin/env bash
# Prepare a unitree_rl_mjlab checkout for the sim2sim of OUR walking policy:
#   1. simulate/config.yaml: robot G1-23DoF, elastic band on (the robot starts hanging)
#   2. deploy/robots/g1_23dof/config/config.yaml: the dance state off (its motion file is
#      not shipped, and g1_ctrl aborts at start-up without it)
#   3. policy/policy.onnx (+ policy.onnx.data) and policy/deploy.yaml of this repo
#      -> deploy/robots/g1_23dof/config/policy/velocity/v0/
# The original files are kept once as *.orig. Running it twice is harmless.
#
#   bash sim2sim/apply.sh [path to unitree_rl_mjlab]
#   (default: $UNITREE_RL_MJLAB, else ~/g1_ws/unitree_rl_mjlab)
# Then rebuild nothing: the simulator and g1_ctrl read these files at start-up.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${1:-${UNITREE_RL_MJLAB:-$HOME/g1_ws/unitree_rl_mjlab}}"
SIM_CFG="$URL/simulate/config.yaml"
CTRL_CFG="$URL/deploy/robots/g1_23dof/config/config.yaml"
POL_DIR="$URL/deploy/robots/g1_23dof/config/policy/velocity/v0"

for f in "$SIM_CFG" "$CTRL_CFG"; do
  [ -f "$f" ] || { echo "Not found: $f (is $URL a unitree_rl_mjlab checkout?)"; exit 1; }
done

backup() { [ -f "$1.orig" ] || cp "$1" "$1.orig"; }

# 1. simulator: G1-23DoF + elastic band
backup "$SIM_CFG"
python3 - "$SIM_CFG" <<'EOF'
import re, sys
path = sys.argv[1]
out = []
for line in open(path).read().splitlines():
    if re.match(r'^(robot|robot_scene):', line):           # any active robot -> comment
        line = "#" + line
    if re.match(r'^#\s*robot:\s*"g1_23dof"', line) or \
       re.match(r'^#\s*robot_scene:\s*".*scene_g1_23dof\.xml"', line):
        line = line.lstrip("#").lstrip()                   # our robot -> active
    if re.match(r'^enable_elastic_band:', line):
        line = re.sub(r'^enable_elastic_band:\s*\d+', 'enable_elastic_band: 1', line)
    out.append(line)
text = "\n".join(out) + "\n"
active = re.findall(r'^robot:\s*"([^"]+)"', text, re.M)
if active != ["g1_23dof"]:
    sys.exit("simulate/config.yaml: expected one active robot g1_23dof, got %s" % active)
open(path, "w").write(text)
EOF
echo "simulator  : G1-23DoF, elastic band on        ($SIM_CFG)"

# 2. g1_ctrl: dance state off (only the 3 lines in the list of enabled states)
backup "$CTRL_CFG"
sed -i '/^    Mimic_Dance1_subject2:$/,/^      type: Mimic$/ s/^/#/' "$CTRL_CFG"
echo "g1_ctrl    : dance state off                  ($CTRL_CFG)"

# 3. the policy of this repo
if [ -f "$REPO/policy/policy.onnx" ]; then
  mkdir -p "$POL_DIR/exported" "$POL_DIR/params"
  cp "$REPO/policy/policy.onnx" "$POL_DIR/exported/"
  [ -f "$REPO/policy/policy.onnx.data" ] && cp "$REPO/policy/policy.onnx.data" "$POL_DIR/exported/"
  if [ -f "$REPO/policy/deploy.yaml" ]; then
    [ -f "$POL_DIR/params/deploy.yaml" ] && backup "$POL_DIR/params/deploy.yaml"
    cp "$REPO/policy/deploy.yaml" "$POL_DIR/params/deploy.yaml"
  fi
  echo "policy     : $(md5sum "$REPO/policy/policy.onnx" | cut -c1-12) -> $POL_DIR/exported/"
else
  echo "policy     : no policy/policy.onnx in this repo yet (scripts/import_run.sh adds it)"
fi

cat <<EOF

Ready. Start, in this order and in 3 terminals:
  1) sudo python3 $REPO/sim2sim/keyboard_pad.py
  2) cd $URL && ./simulate/build/unitree_mujoco
  3) cd $URL/deploy/robots/g1_23dof/build && ./g1_ctrl --network=lo
To undo: copy the *.orig files back.
EOF
