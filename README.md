# G1-23DoF walking with reinforcement learning

A walking policy for the Unitree G1 humanoid (23 joints), trained with PPO in
[mjlab](https://github.com/mujocolab/mjlab) using Unitree's velocity-tracking recipe
([unitree_rl_mjlab](https://github.com/unitreerobotics/unitree_rl_mjlab), task
`Unitree-G1-23Dof-Flat`), and checked in a second simulator (sim2sim) with the same control
program that runs on the real robot.

This is phase 1 of a step-by-step project: **walking** (this phase), then getting up after a
fall, then kicking. Each phase starts from the policy of the previous one.

This README is the **replication guide**: everything needed to train, check and deploy the
same policy.

| Step | Status |
| --- | --- |
| Train in mjlab (GPU) | done: run `2026-10-20_14-05-09`, checkpoint `model_10298.pt` |
| Sim2sim in unitree_mujoco with `g1_ctrl` | done 2026-11-01: it walks |
| Real robot | next |
| Getting up after a fall | not trained (see [Limitations](#10-limitations-and-next-steps)) |

## Contents

1. [Repository layout](#1-repository-layout)
2. [Requirements](#2-requirements)
3. [Setup](#3-setup)
4. [Train](#4-train)
5. [Check the policy in mjlab and keep the run](#5-check-the-policy-in-mjlab-and-keep-the-run)
6. [Sim2sim](#6-sim2sim-unitree_mujoco--g1_ctrl)
7. [Real robot](#7-real-robot)
8. [The training problem, term by term](#8-the-training-problem-term-by-term) (observations, actions, rewards and penalties, terminations, randomization, PPO)
9. [Known issues and troubleshooting](#9-known-issues-and-troubleshooting)
10. [Limitations and next steps](#10-limitations-and-next-steps)
11. [Credits](#11-credits)

## 1. Repository layout

```
g1-walking-rl/
├── README.md                 this guide
├── training/
│   ├── train.sh              the training command
│   ├── params/               env.yaml + agent.yaml of the imported run (exact configuration)
│   ├── RUN.md, VERSIONS.md   which run, software and GPU            (scripts/import_run.sh)
├── policy/                   policy.onnx, last model_<N>.pt, deploy.yaml (scripts/import_run.sh)
├── sim2sim/
│   ├── apply.sh              prepares a unitree_rl_mjlab checkout for the sim2sim
│   ├── keyboard_pad.py       virtual gamepad driven from the keyboard (no real pad needed)
│   ├── simulate_config.yaml  simulator settings we use (reference copy)
│   └── g1_ctrl_config.yaml   controller states we use (reference copy)
└── scripts/
    ├── import_run.sh         copies a finished training run into this repo
    └── check_public.sh       before a push: looks for words that must not be published
```

A `notes/` folder for personal notes can live next to these files: it is in `.gitignore`, so it
is never uploaded.

The training code itself is Unitree's (`unitree_rl_mjlab`, Apache-2.0); this repository holds
our run, configuration, tools and documentation, so the same result can be reproduced and every
change is recorded with git.

## 2. Requirements

| | Training | Sim2sim and real robot |
| --- | --- | --- |
| OS | Linux (Unitree recommends Ubuntu 22.04) | Ubuntu (Unitree builds its SDK on 20.04; newer versions work) |
| GPU | NVIDIA, driver 550 or later (MuJoCo Warp runs on CUDA) | any (the simulator draws one robot) |
| Software | Python 3.11 environment with `unitree_rl_mjlab` (pins `mjlab==1.2.0`, `mujoco-warp==3.5.0` at the time of writing) | `unitree_sdk2` (current version, with `dds_wrapper`), CycloneDDS (comes with it), CMake, a C++17 compiler |
| Other | | a gamepad (Xbox layout), or `sim2sim/keyboard_pad.py` |

The exact versions of our run are in `training/VERSIONS.md`.

## 3. Setup

The commands below keep the checkouts in `~/g1_ws`. Use any folder: the scripts of this repo
take the `unitree_rl_mjlab` path as an argument, or from the `UNITREE_RL_MJLAB` environment
variable (and `UNITREE_SDK2` for the SDK).

```bash
mkdir -p ~/g1_ws && cd ~/g1_ws
git clone https://github.com/unitreerobotics/unitree_rl_mjlab.git
cd unitree_rl_mjlab
python3.11 -m venv .venv && source .venv/bin/activate      # or a conda env with Python 3.11
pip install -e .

# For the sim2sim and the robot (C++ side):
sudo apt install -y build-essential cmake git libyaml-cpp-dev libeigen3-dev libboost-dev \
  libboost-program-options-dev libfmt-dev libspdlog-dev libglfw3-dev zlib1g-dev python3-evdev
git clone https://github.com/unitreerobotics/unitree_sdk2.git ~/g1_ws/unitree_sdk2
cd ~/g1_ws/unitree_sdk2 && mkdir -p build && cd build && cmake .. && make -j4 && sudo make install && sudo ldconfig
```

Install `unitree_sdk2` to the default prefix (`/usr/local`): `g1_ctrl`'s CMake looks for the DDS
headers in `/usr/local/include/ddscxx`.

## 4. Train

```bash
bash training/train.sh ~/g1_ws/unitree_rl_mjlab 4096
# = cd ~/g1_ws/unitree_rl_mjlab && python scripts/train.py Unitree-G1-23Dof-Flat --env.scene.num-envs=4096
```

- Output: `logs/rsl_rl/g1_23dof_velocity/<date_time>/` with `model_<N>.pt` every 100
  iterations, `policy.onnx` re-exported at every save, `params/env.yaml` and
  `params/agent.yaml`, and the TensorBoard events (`tensorboard --logdir logs/rsl_rl`).
- One iteration = 24 steps of every robot (98 304 transitions with 4096 robots) + one PPO update.
  The configured length is 10 001 iterations (our run went to 10 298).
- Lower `num-envs` if the GPU runs out of memory (fewer transitions per iteration: expect
  slower, noisier learning).
- What to watch: mean reward going up and flattening; `Episode_Reward/track_linear_velocity`
  and `track_angular_velocity` close to their maximum (the weight × episode length in seconds);
  `Episode_Termination/fell_over` going towards 0 next to `time_out`; `Mean action std` going
  down slowly.

## 5. Check the policy in mjlab and keep the run

```bash
cd ~/g1_ws/unitree_rl_mjlab && source .venv/bin/activate
python scripts/play.py Unitree-G1-23Dof-Flat \
  --checkpoint_file=logs/rsl_rl/g1_23dof_velocity/<run>/model_<N>.pt

# copy the run into this repo (policy, last checkpoint, configuration, versions) and commit it
bash scripts/import_run.sh ~/g1_ws/unitree_rl_mjlab/logs/rsl_rl/g1_23dof_velocity/<run>
git add -A && git commit -m "Import walking run <run>"
```

## 6. Sim2sim (unitree_mujoco + g1_ctrl)

The policy runs in a second simulator (MuJoCo on the CPU, no randomization) through **the same
program and files that run on the robot**: `g1_ctrl`, `policy.onnx`, `deploy.yaml`. The two
talk over DDS on the local network interface (`lo`), exactly as `g1_ctrl` talks to the real
robot over Ethernet. If something is wrong in the deployment (observation order, scales,
gains, timing), it shows up here, without risk.

**Once:**

```bash
cd <this repo>
bash sim2sim/apply.sh ~/g1_ws/unitree_rl_mjlab       # G1-23DoF + elastic band, dance state off, our policy
cd ~/g1_ws/unitree_rl_mjlab/simulate && mkdir -p build && cd build && cmake .. && make -j4
cd ~/g1_ws/unitree_rl_mjlab/deploy/robots/g1_23dof && mkdir -p build && cd build && cmake .. && make -j4
```

**Every time, in this order, in 3 terminals:**

```bash
sudo python3 sim2sim/keyboard_pad.py                     # 1. gamepad (skip with a real pad)
cd ~/g1_ws/unitree_rl_mjlab && ./simulate/build/unitree_mujoco          # 2. simulator
cd ~/g1_ws/unitree_rl_mjlab/deploy/robots/g1_23dof/build && ./g1_ctrl --network=lo   # 3. controller
```

| Where | Key | Action |
| --- | --- | --- |
| gamepad terminal | `1` | stand up (LT + d-pad up): fixed standing posture in 3 s |
| simulator window | `↓` or `8` / `↑` or `7` | lengthen / shorten the elastic band (lower / raise the robot) |
| simulator window | `9` | release (or hook again) the elastic band |
| gamepad terminal | `2` | start the policy (RT + A) |
| gamepad terminal | `w s` / `a d` / `q e` | forward-back / sideways / turn, ±0.1 per press |
| gamepad terminal | `space` | all speeds to 0 |
| gamepad terminal | `0` | passive (LT + B): motors off, damping only (emergency stop) |
| simulator window | `Backspace` | reset the simulation |

Sequence: `1` while hanging → `↓` until the feet carry the weight → `9` → `2` → walk.
Passes if: it stands still for a minute with zero command, walks slowly in every direction
without shaking or falling, survives sudden command changes, `0` always stops it, and the
`g1_ctrl` terminal shows no errors.

**With a real gamepad** instead of the keyboard: an Xbox controller, or a PlayStation 4/5
controller (on Linux it reports the same button and axis numbers for everything `g1_ctrl`
uses; keep `joystick_type: "xbox"`). Connect it by USB before starting the simulator, do not
start `keyboard_pad.py`, and check it with `jstest /dev/input/js0` (package `joystick`):
A/✕ = button 0, B/◯ = button 1, LT/L2 = axis 2, RT/R2 = axis 5, d-pad = axes 6-7.

| Action | Xbox | PlayStation |
| --- | --- | --- |
| stand up | LT + d-pad up | L2 + d-pad up |
| start the policy | RT + A | R2 + ✕ |
| passive | LT + B | L2 + ◯ |
| walk / turn | left stick / right stick (full deflection = 1 m/s forward, 1 rad/s) | same |

## 7. Real robot

Same `g1_ctrl`, same files; only the network interface changes.

1. Robot hanging on its gantry. Power on (short press, then hold 2 s); after about a minute it
   is in zero-torque mode.
2. Debug mode: `L2 + R2` on Unitree's remote. This switches Unitree's own locomotion off (else
   `g1_ctrl` reports that another process uses the `lowcmd` channel). Reboot to leave it.
3. Laptop on the robot's Ethernet: address `192.168.123.222`, netmask `255.255.255.0`.
4. `./g1_ctrl --network=<ethernet interface>` (see `ip a`). Same states as in the sim2sim:
   `LT + up` (L2 + up on Unitree's remote) stands up; lower the robot until the feet carry the
   weight; `RT + A` (R2 + A) starts the policy; `LT + B` (L2 + B) = passive. There is **no**
   automatic stop if the robot falls ([9.1](#91-known-issues-in-the-deployment-chain), issue 1):
   keep `L2 + B` ready.
5. Safety: one person only for the remote with `L2 + B` ready; nobody near the robot; gantry or
   rope for the first tests; check battery and motor temperatures; never two programs sending
   `lowcmd`; start slowly (standing, then 0.1-0.3 m/s).

## 8. The training problem, term by term

Everything below is Unitree's G1-23DoF flat velocity task as configured in `unitree_rl_mjlab`
(`src/tasks/velocity/velocity_env_cfg.py`, `config/g1_23dof/env_cfgs.py`, `config/g1_23dof/rl_cfg.py`).
The configuration of our run is stored in `training/params/`.

### 8.1 Task and simulation

| | |
| --- | --- |
| Goal | follow a velocity command (forward, sideways, turning) with a natural gait, without falling |
| Simulator | MuJoCo Warp (GPU) through mjlab, flat ground |
| Physics step | 5 ms (200 Hz), 10 solver iterations |
| Policy rate | every 4 physics steps = 20 ms (**50 Hz**) |
| Episode | 20 s (1000 policy steps), or until a fall |
| Parallel robots | 4096 (Unitree's command); each starts within ±0.5 m of its origin, random heading |

### 8.2 Observations

Actor (the policy, 80 numbers; the same 80 are built by `g1_ctrl` on the robot from
`deploy.yaml`):

| Term | Size | What | Training noise (uniform) |
| --- | --- | --- | --- |
| `base_ang_vel` | 3 | angular velocity of the pelvis IMU (rad/s) | ±0.2 |
| `projected_gravity` | 3 | gravity direction in the pelvis frame (tilt) | ±0.05 |
| `command` | 3 | commanded vx, vy (m/s) and yaw rate (rad/s) | — |
| `phase` | 2 | sin, cos of a 0.6 s gait clock; 0, 0 when the command is below 0.1 | — |
| `joint_pos` | 23 | joint angle minus default angle (rad) | ±0.01 |
| `joint_vel` | 23 | joint velocities (rad/s) | ±1.5 |
| `actions` | 23 | previous action | — |

Critic (value function, 95 numbers, training only, no noise): the 80 above plus pelvis linear
velocity (3), foot heights (2), foot air times (2), foot contacts (2), foot contact forces (6,
sign × log(1 + |F|)). The critic may use information the robot cannot measure because it is
never deployed (asymmetric actor-critic). Both networks normalize their inputs with running
mean and variance.

### 8.3 Actions and motor control

23 numbers per step → joint position targets `q* = q_default + scale × a`, tracked by a PD
controller in every motor: `τ = kp (q* − q) − kd q̇`, limited to the motor's torque.
The gains come from the motor physics: each joint behaves like a 10 Hz spring with damping
ratio 2 for the reflected inertia J of its gearbox (`kp = J ω²`, `kd = 2 ζ J ω`, ω = 2π·10 rad/s),
and `scale = 0.25 × τ_max / kp`.

| Motor (joints) | kp (N·m/rad) | kd (N·m·s/rad) | τ max (N·m) | no-load speed (rad/s) | action scale (rad) |
| --- | --- | --- | --- | --- | --- |
| 7520-22 (knees, hip roll) | 99.1 | 6.3 | 139 | 20 | 0.35 |
| 7520-14 (hip pitch/yaw, waist yaw) | 40.2 | 2.6 | 88 | 32 | 0.55 |
| 2 × 5020 (ankle pitch/roll) | 28.5 | 1.8 | 50 | 37 | 0.44 |
| 5020 (shoulders, elbows, wrist roll) | 14.3 | 0.9 | 25 | 37 | 0.44 |

Default pose (rad): hip pitch −0.1, knee 0.3, ankle pitch −0.2, shoulder pitch 0.35, shoulder
roll ±0.18, elbow 0.87, all others 0. Joint order and gains as `g1_ctrl` uses them:
`policy/deploy.yaml`.

### 8.4 Commands and curriculum

| | |
| --- | --- |
| Sampling | vx, vy, yaw rate uniform in the ranges below, new values every 3-8 s |
| Standing | 5 % of the commands are zero (learn to stand still) |
| Heading control | the yaw-rate command is 0.5 × (random target heading − current heading), limited to ±1 rad/s |
| Curriculum | iterations 0-5000: vx −0.5…1.0, vy −0.5…0.5 m/s; after: vx −1.0…2.0, vy −1.0…1.0 m/s; yaw ±1 rad/s |
| On the robot | `deploy.yaml` limits the joystick to vx −0.5…1.0, vy −0.5…0.5 m/s, yaw ±1 rad/s |

### 8.5 Rewards and penalties

Every term is computed per robot and step, multiplied by its weight **and by the step time
(0.02 s)**, and summed. Positive weights are rewards, negative weights are penalties. "When
moving" = only when the command is above 0.1.

| Term | Weight | Formula | Why |
| --- | --- | --- | --- |
| `track_linear_velocity` | +1.0 | exp(−(‖v_cmd,xy − v_xy‖² + 2 v_z²) / 0.25) | follow the commanded forward and sideways speed, no bouncing |
| `track_angular_velocity` | +1.0 | exp(−((ω_cmd − ω_z)² + 0.05 ‖ω_xy‖²) / 0.5) | follow the commanded turning speed |
| `pose` (variable posture) | +1.0 | exp(−mean((q − q_default)² / σ²)); σ per joint, depends on speed: standing 0.05 rad for all; walking 0.1-0.5 (knees and hip pitch loosest, ankle roll and arms tightest); running (≥ 1.5) looser | natural posture, more freedom the faster it goes |
| `foot_gait` | +0.5 | fraction of the feet whose contact matches a 0.6 s clock (feet half a period apart, stance 56 % of the period); when moving | alternating left-right rhythm |
| `is_terminated` | −200 | 1 in the step the robot falls (not at the time limit) | do not fall |
| `joint_pos_limits` | −10 | how far joints go beyond 90 % of their range | keep a margin from the mechanical limits |
| `body_orientation_l2` | −1.0 | ‖g_xy‖² of the torso (squared tilt) | stay upright |
| `foot_clearance` | −1.0 | Σ_feet \|z_foot − 0.10 m\| × ‖v_foot,xy‖; when moving | lift the swinging foot about 10 cm |
| `stand_still` | −1.0 | Σ (q − q_default)²; only when the command is ≤ 0.1 | stand still and straight when told to stop |
| `self_collisions` | −1.0 | physics substeps with a self-contact force above 10 N | no leg-leg or arm-body hits |
| `foot_slip` | −0.25 | Σ_feet ‖v_foot,xy‖² while in contact; when moving | no sliding feet |
| `action_rate_l2` | −0.05 | Σ (a_t − a_t−1)² | smooth commands to the motors |
| `body_ang_vel` | −0.05 | ‖ω_xy‖² of the torso | no wobbling |
| `angular_momentum` | −0.025 | ‖L‖² of the whole body | counter-rotation: natural arm swing |
| `soft_landing` | −0.001 | Σ contact force at the moment a foot lands; when moving | soft footfalls (less impact on the hardware) |
| `joint_acc_l2` | −2.5e-7 | Σ q̈² | smooth joint motion |

Notes for anyone tuning it:
- Because of the × 0.02, a fall costs 200 × 0.02 = 4, about two seconds of good tracking
  (≈ 2 per second for the two tracking terms together).
- The tracking terms are bounded (exp of minus an error, at most 1), so the policy cannot
  farm them; the penalties are what shape the style.
- `foot_gait` + `phase` give the policy a clock: without them humanoid gaits tend to shuffle
  or hop.

### 8.6 Terminations

| Term | Condition | Counts as |
| --- | --- | --- |
| `fell_over` | torso tilted more than 70° | failure (−200 × 0.02, no future value) |
| `time_out` | 20 s | truncation: no penalty, the value of the last state is bootstrapped |

### 8.7 Domain randomization and perturbations

| What | Range | When |
| --- | --- | --- |
| Foot friction | 0.3-1.6 (all foot geoms share it) | robot creation |
| Joint encoder bias | ±0.015 rad | robot creation |
| Torso center of mass | ±5 cm per axis | robot creation |
| Pushes | velocity impulse: ±0.5 m/s horizontal, ±0.4 m/s vertical, ±0.52 rad/s roll/pitch, ±0.78 rad/s yaw | every 5-6 s |
| Sensor noise | see 8.2 | every step |

### 8.8 PPO and networks (rsl_rl)

| Setting | Value |
| --- | --- |
| Actor | MLP 80 → 512 → 256 → 128 → 23, ELU, Gaussian output with a learned std per joint (initial 1.0); ≈ 209 k parameters |
| Critic | MLP 95 → 512 → 256 → 128 → 1, ELU; ≈ 214 k parameters |
| Steps per robot per iteration | 24 |
| Discount γ / GAE λ | 0.99 / 0.95 |
| Clip ε | 0.2 (also on the value loss) |
| Epochs × mini-batches | 5 × 4 |
| Learning rate | 1e-3, adaptive: divided by 1.5 if KL > 0.02, multiplied by 1.5 if KL < 0.005 (target 0.01) |
| Value loss coefficient | 1.0 |
| Entropy coefficient | 0.01 |
| Max gradient norm | 1.0 |
| Iterations | 10 001 configured (checkpoint every 100) |

## 9. Known issues and troubleshooting

### 9.1 Known issues in the deployment chain

Found while reviewing `unitree_rl_mjlab` at commit `1425b15` (still the latest on GitHub on
2026-11-01). The policy walks in the sim2sim with all three; fix them, or at least keep them in
mind, before the real robot. Paths are relative to `unitree_rl_mjlab/`; after editing a C++ file,
rebuild `g1_ctrl` (`cd deploy/robots/g1_23dof/build && make -j$(nproc)`).

1. **No automatic stop when the robot falls.** In `deploy/include/isaaclab/envs/mdp/terminations.h`,
   `bad_orientation()` returns `false` (the tilt check is commented out), so the policy state never
   goes passive by itself: after a fall the policy keeps running until `LT + B`. To restore the
   1 rad check, replace `return false;` with the commented line,
   `return std::fabs(std::acos(-data[2])) > limit_angle;`, and rebuild. Test it in the sim2sim by
   pushing the walking robot over with the mouse (double-click the torso, then Ctrl + right-drag):
   `g1_ctrl` prints `FSM: Change state from Velocity to Passive`.
2. **Four right-arm motors keep the FixStand gains under the policy (G1-23DoF only).** In
   `deploy/include/FSM/State_RLBase.h`, `enter()` writes the gains of policy joint `i` to motor `i`,
   while `run()` writes the targets to motor `joint_ids_map[i]`. With the 23-DoF map, motors 23-26
   (right shoulder roll and yaw, right elbow, right wrist roll) keep kp 40 / kd 10 from FixStand
   instead of the trained 14.3 / 0.9. Fix, inside the loop of `enter()`:

   ```cpp
   auto & motor = lowcmd->msg_.motor_cmd()[static_cast<int>(env->robot->data.joint_ids_map[i])];
   motor.kp() = env->robot->data.joint_stiffness[i];
   motor.kd() = env->robot->data.joint_damping[i];
   motor.dq() = 0;
   motor.tau() = 0;
   ```

   and rebuild. Nothing changes for robots with an identity map (G1 29-DoF). `State_Mimic.cpp`
   has the same pattern.
3. **Right ankle torque limited to ±25 N·m in the sim2sim scene.** In
   `src/assets/robots/unitree_g1/xmls/scene_g1_23dof.xml`, lines 239-240, the right ankle motors
   have `ctrlrange="-25 25"`; the left ones, the joints themselves and the training use ±50. Fix
   (the simulator reads the file at start-up, no rebuild):

   ```bash
   sed -i -E '/name="right_ankle_(pitch|roll)"/ s/ctrlrange="-25 25"/ctrlrange="-50 50"/' \
     src/assets/robots/unitree_g1/xmls/scene_g1_23dof.xml
   ```

### 9.2 Symptoms and fixes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `g1_ctrl` does not build: `unitree/dds_wrapper/...` not found | old `unitree_sdk2` | install the current one (section 3), clean rebuild |
| Simulator: `Error: Joystick open failed.` and it closes | no `/dev/input/js0` | start `sim2sim/keyboard_pad.py` first; `sudo chmod a+r /dev/input/js0`; another number → `joystick_device` in `simulate/config.yaml` |
| Simulator window opens but shows the desktop / `GLXBadDrawable` | OpenGL on a laptop with two GPUs | start it with `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia`, or `__GLX_VENDOR_LIBRARY_NAME=mesa`, or `LIBGL_ALWAYS_SOFTWARE=1` in front |
| `g1_ctrl`: `npz_load: Error! Unable to open file .../dance1_subject2.npz` | the dance state is on but its motion file is not shipped | `sim2sim/apply.sh` (turns that state off) |
| `g1_ctrl` waits for `rt/lowstate` forever | simulator not running (or crashed), or wrong interface | start the simulator; `--network=lo` for the sim2sim |
| `selected interface "lo" is not multicast-capable` | normal on the loopback interface | nothing |
| Real robot does not respond to its remote | left in debug mode | reboot the robot |
| Robot falls as soon as the band is released | released before the feet carried the weight, or still in passive | lower the band more, press `1` (stand) before releasing |

## 10. Limitations and next steps

- **No getting up.** The policy always started standing and every episode ended at 70° of
  tilt, so it has never seen the floor. A humanoid that
  cannot get up needs a person every time it falls. Phase 2: a get-up skill by motion
  imitation (Unitree's tracking pipeline + "fall and get up" clips of the LAFAN1 dataset
  retargeted to the G1), run by `g1_ctrl` as one more state, then hardened with RL from random
  fallen poses.
- Flat ground only; speeds limited to the ranges above.
- Blind walking: no camera, no perception of the surroundings.
- Sim2sim uses the same physics engine family (MuJoCo) as training: it checks the deployment
  chain well, the physics less so.

## 11. Credits

- [unitree_rl_mjlab](https://github.com/unitreerobotics/unitree_rl_mjlab) (Unitree, Apache-2.0):
  task, robot model, deployment program and simulator bridge. `sim2sim/simulate_config.yaml`
  and `sim2sim/g1_ctrl_config.yaml` are modified copies of its configuration files.
- [mjlab](https://github.com/mujocolab/mjlab) (Apache-2.0), [MuJoCo Warp](https://github.com/google-deepmind/mujoco_warp),
  [rsl_rl](https://github.com/leggedrobotics/rsl_rl) (PPO), [unitree_sdk2](https://github.com/unitreerobotics/unitree_sdk2).
- PPO: Schulman et al., 2017, [arXiv:1707.06347](https://arxiv.org/abs/1707.06347);
  massively parallel training for legged robots: Rudin et al., CoRL 2021,
  [arXiv:2109.11978](https://arxiv.org/abs/2109.11978).
