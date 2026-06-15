#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

has_files() {
  local path="$1"
  [[ -d "${path}" ]] || return 1
  find "${path}" -mindepth 1 -maxdepth 2 -print -quit 2>/dev/null | grep -q .
}

BUILD_FOLDER="${BUILD_FOLDER:-v1.0.0}"
CARLA_MAP="${CARLA_MAP:-UBAutonomousProvingGrounds}"
CARLA_MAP_PATH="${CARLA_MAP_PATH:-/Game/Carla/Maps/${CARLA_MAP}}"
CARLA_ARGS="${CARLA_ARGS:--prefernvidia -quality-level=Low -nosound}"

DEFAULT_AUTOWARE_HOST_MAP_DIR="${REPO_DIR}/Autoware/host_data/maps/ub_autonomous_proving_grounds"
DEFAULT_AUTOWARE_MAP_PATH="/host_data/maps/ub_autonomous_proving_grounds"
LEGACY_AUTOWARE_HOST_MAP_DIR="${REPO_DIR}/Autoware/host_data/ub_autonomous_proving_grounds"
LEGACY_AUTOWARE_MAP_PATH="/host_data/ub_autonomous_proving_grounds"

if [[ -z "${AUTOWARE_HOST_MAP_DIR:-}" && -z "${AUTOWARE_MAP_PATH:-}" ]] && has_files "${LEGACY_AUTOWARE_HOST_MAP_DIR}" && ! has_files "${DEFAULT_AUTOWARE_HOST_MAP_DIR}"; then
  AUTOWARE_HOST_MAP_DIR="${LEGACY_AUTOWARE_HOST_MAP_DIR}"
  AUTOWARE_MAP_PATH="${LEGACY_AUTOWARE_MAP_PATH}"
fi

AUTOWARE_DOCKER_DIR="${AUTOWARE_DOCKER_DIR:-${REPO_DIR}/Autoware/ub-lincoln-docker/docker}"
AUTOWARE_HOST_MAP_DIR="${AUTOWARE_HOST_MAP_DIR:-${DEFAULT_AUTOWARE_HOST_MAP_DIR}}"
AUTOWARE_MAP_PATH="${AUTOWARE_MAP_PATH:-${DEFAULT_AUTOWARE_MAP_PATH}}"
AUTOWARE_SERVICE="${AUTOWARE_SERVICE:-autoware}"
AUTOWARE_CARLA_HOST="${AUTOWARE_CARLA_HOST:-127.0.0.1}"
AUTOWARE_VEHICLE_MODEL="${AUTOWARE_VEHICLE_MODEL:-sample_vehicle}"
AUTOWARE_SENSOR_MODEL="${AUTOWARE_SENSOR_MODEL:-awsim_sensor_kit}"
UB_AUTOWARE_INSTALL_PY_DEPS="${UB_AUTOWARE_INSTALL_PY_DEPS:-1}"
UB_AUTOWARE_CARLA_TOP_LIDAR_ONLY="${UB_AUTOWARE_CARLA_TOP_LIDAR_ONLY:-1}"
UB_AUTOWARE_PATCH_CARLA_BRIDGE="${UB_AUTOWARE_PATCH_CARLA_BRIDGE:-1}"
UB_AUTOWARE_EGO_ONLY_PERCEPTION="${UB_AUTOWARE_EGO_ONLY_PERCEPTION:-1}"
UB_KEEP_CARLA="${UB_KEEP_CARLA:-0}"

DRY_RUN=0
CARLA_STARTED=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run] [--help]

Start rendered CARLA on the UB autonomous proving grounds map, then launch
Autoware's CARLA e2e simulator in the foreground.

Defaults:
  BUILD_FOLDER=${BUILD_FOLDER}
  CARLA_MAP=${CARLA_MAP}
  CARLA_ARGS=${CARLA_ARGS}
  AUTOWARE_MAP_PATH=${AUTOWARE_MAP_PATH}
  AUTOWARE_SERVICE=${AUTOWARE_SERVICE}
  AUTOWARE_CARLA_HOST=${AUTOWARE_CARLA_HOST}
  AUTOWARE_VEHICLE_MODEL=${AUTOWARE_VEHICLE_MODEL}
  AUTOWARE_SENSOR_MODEL=${AUTOWARE_SENSOR_MODEL}
  UB_AUTOWARE_INSTALL_PY_DEPS=${UB_AUTOWARE_INSTALL_PY_DEPS}
  UB_AUTOWARE_CARLA_TOP_LIDAR_ONLY=${UB_AUTOWARE_CARLA_TOP_LIDAR_ONLY}
  UB_AUTOWARE_PATCH_CARLA_BRIDGE=${UB_AUTOWARE_PATCH_CARLA_BRIDGE}
  UB_AUTOWARE_EGO_ONLY_PERCEPTION=${UB_AUTOWARE_EGO_ONLY_PERCEPTION}

Useful overrides:
  BUILD_FOLDER=v1.0.0 $(basename "$0")
  CARLA_ARGS="-prefernvidia -quality-level=Epic" $(basename "$0")
  AUTOWARE_SERVICE=<compose-service> $(basename "$0")
  AUTOWARE_CARLA_HOST=<host-ip> $(basename "$0")
  UB_AUTOWARE_INSTALL_PY_DEPS=0 $(basename "$0")
  UB_AUTOWARE_CARLA_TOP_LIDAR_ONLY=0 $(basename "$0")
  UB_AUTOWARE_PATCH_CARLA_BRIDGE=0 $(basename "$0")
  UB_AUTOWARE_EGO_ONLY_PERCEPTION=0 $(basename "$0")
  UB_KEEP_CARLA=1 $(basename "$0")

Options:
  --dry-run  Validate prerequisites and print the commands without starting CARLA.
  --help     Show this help text.
EOF
}

setup_hint() {
  cat <<EOF

Setup hints:
  CARLA build:
    bash scripts/install_ub_carla.sh ${BUILD_FOLDER}

  Autoware submodule, image, and UB HD map:
    cd Autoware
    ./setup_autoware.sh

  If Autoware uses a different Docker Compose service name:
    AUTOWARE_SERVICE=<service-name> CARLA/start_autoware_carla.sh
EOF
}

collect_preflight_failures() {
  local failures_ref="$1"
  local -n preflight_failures="${failures_ref}"

  if ! command -v docker >/dev/null 2>&1; then
    preflight_failures+=("Docker is not installed or not on PATH.")
  elif ! docker compose version >/dev/null 2>&1; then
    preflight_failures+=("Docker Compose v2 is unavailable. Install the Docker Compose plugin so 'docker compose' works.")
  fi

  if [[ ! -x "${SCRIPT_DIR}/Builds/${BUILD_FOLDER}/CarlaUE4.sh" ]]; then
    preflight_failures+=("Missing executable CARLA build: ${SCRIPT_DIR}/Builds/${BUILD_FOLDER}/CarlaUE4.sh")
  fi

  if [[ ! -d "${AUTOWARE_DOCKER_DIR}" ]]; then
    preflight_failures+=("Missing Autoware Docker directory: ${AUTOWARE_DOCKER_DIR}")
  elif [[ ! -f "${AUTOWARE_DOCKER_DIR}/compose.yml" && ! -f "${AUTOWARE_DOCKER_DIR}/docker-compose.yml" && ! -f "${AUTOWARE_DOCKER_DIR}/docker-compose.yaml" ]]; then
    preflight_failures+=("Autoware Docker directory does not contain a Compose file: ${AUTOWARE_DOCKER_DIR}")
  fi

  if ! has_files "${AUTOWARE_HOST_MAP_DIR}"; then
    preflight_failures+=("Missing or empty Autoware UB HD map directory: ${AUTOWARE_HOST_MAP_DIR}")
  fi

  if [[ -z "${DISPLAY:-}" ]]; then
    preflight_failures+=("DISPLAY is not set. Run from a graphical Linux session or configure X11 forwarding.")
  fi

  if [[ ! -d /tmp/.X11-unix ]]; then
    preflight_failures+=("Missing /tmp/.X11-unix. Rendered CARLA needs the host X11 socket mounted into Docker.")
  fi
}

run_preflight() {
  local failures=()
  collect_preflight_failures failures

  if [[ ${#failures[@]} -gt 0 ]]; then
    echo "Preflight failed:"
    local failure
    for failure in "${failures[@]}"; do
      echo "  - ${failure}"
    done
    setup_hint
    return 1
  fi
}

print_dry_run() {
  cat <<EOF
Dry run passed. The launcher would run:

  cd ${SCRIPT_DIR}
  BUILD_FOLDER=${BUILD_FOLDER} \\
  CARLA_MAP_PATH=${CARLA_MAP_PATH} \\
  CARLA_ARGS=${CARLA_ARGS} \\
  docker compose up --build -d carla redis map-loader

  cd ${AUTOWARE_DOCKER_DIR}
  docker compose up -d ${AUTOWARE_SERVICE}
  docker compose exec ${AUTOWARE_SERVICE} bash -lc 'ros2 launch autoware_launch e2e_simulator.launch.xml ...'

Autoware launch arguments:
  map_path:=${AUTOWARE_MAP_PATH}
  vehicle_model:=${AUTOWARE_VEHICLE_MODEL}
  sensor_model:=${AUTOWARE_SENSOR_MODEL}
  simulator_type:=carla
  host:=${AUTOWARE_CARLA_HOST}
  carla_map:=${CARLA_MAP}
  install_python_deps:=${UB_AUTOWARE_INSTALL_PY_DEPS}
  carla_top_lidar_only:=${UB_AUTOWARE_CARLA_TOP_LIDAR_ONLY}
  patch_carla_bridge:=${UB_AUTOWARE_PATCH_CARLA_BRIDGE}
  ego_only_perception:=${UB_AUTOWARE_EGO_ONLY_PERCEPTION}
EOF
}

cleanup() {
  local exit_code="$?"

  if [[ "${CARLA_STARTED}" -eq 1 && "${UB_KEEP_CARLA}" != "1" ]]; then
    echo "Stopping CARLA Compose stack. Set UB_KEEP_CARLA=1 to leave it running."
    cd "${SCRIPT_DIR}"
    docker compose down >/dev/null 2>&1 || true
  fi

  exit "${exit_code}"
}

wait_for_map_loader() {
  local map_loader_id=""
  local status=""

  for _ in {1..30}; do
    map_loader_id="$(docker compose ps -a -q map-loader 2>/dev/null || true)"
    if [[ -n "${map_loader_id}" ]]; then
      break
    fi
    sleep 1
  done

  if [[ -z "${map_loader_id}" ]]; then
    echo "Error: map-loader container was not created." >&2
    docker compose ps >&2 || true
    return 1
  fi

  echo "Waiting for CARLA map loader to finish..."
  status="$(docker wait "${map_loader_id}")"

  if [[ "${status}" != "0" ]]; then
    echo "Error: map-loader exited with status ${status}." >&2
    docker compose logs map-loader >&2 || true
    return 1
  fi

  echo "CARLA map loaded: ${CARLA_MAP}"
}

start_carla() {
  cd "${SCRIPT_DIR}"

  export BUILD_FOLDER
  export CARLA_ARGS
  export CARLA_MAP_PATH
  export XAUTHORITY="${XAUTHORITY:-/run/user/$(id -u)/gdm/Xauthority}"
  if [[ ! -f "${XAUTHORITY}" && -f "${HOME}/.Xauthority" ]]; then
    export XAUTHORITY="${HOME}/.Xauthority"
  fi

  if command -v xhost >/dev/null 2>&1; then
    xhost +local:root >/dev/null || echo "Warning: xhost did not grant local root X11 access. CARLA may fail to render." >&2
  fi

  echo "Starting rendered CARLA Compose stack..."
  CARLA_STARTED=1
  docker compose up --build -d carla redis map-loader
  wait_for_map_loader
}

shell_quote() {
  printf "%q" "$1"
}

launch_autoware() {
  local launch_cmd
  local exec_args=(exec)

  cd "${AUTOWARE_DOCKER_DIR}"

  echo "Starting Autoware Compose service: ${AUTOWARE_SERVICE}"
  docker compose up -d "${AUTOWARE_SERVICE}"

  if [[ ! -t 0 ]]; then
    exec_args+=(-T)
  fi

  launch_cmd="
set -eo pipefail
if [[ -f /opt/ros/humble/setup.bash ]]; then
  source /opt/ros/humble/setup.bash
fi
if [[ -f /autoware/install/setup.bash ]]; then
  source /autoware/install/setup.bash
fi
UB_BACKGROUND_PIDS=\"\"
if [[ $(shell_quote "${UB_AUTOWARE_INSTALL_PY_DEPS}") == 1 ]]; then
  python3 - <<'PY' || python3 -m pip install --upgrade carla==0.9.16 transforms3d==0.4.2
import carla
import transforms3d

def version_tuple(version):
    parts = []
    for part in version.split('.'):
        digits = ''.join(ch for ch in part if ch.isdigit())
        if digits:
            parts.append(int(digits))
    return tuple(parts)

if version_tuple(transforms3d.__version__) < (0, 4, 2):
    raise SystemExit(f'transforms3d {transforms3d.__version__} is older than 0.4.2')
PY
fi
if [[ $(shell_quote "${UB_AUTOWARE_CARLA_TOP_LIDAR_ONLY}") == 1 ]]; then
  AUTOWARE_SENSOR_MODEL_FOR_CARLA=$(shell_quote "${AUTOWARE_SENSOR_MODEL}") python3 - <<'PY'
import os
from pathlib import Path

sensor_model = os.environ['AUTOWARE_SENSOR_MODEL_FOR_CARLA']
launch_path = Path(
    f'/autoware/install/{sensor_model}_launch/share/'
    f'{sensor_model}_launch/launch/lidar.launch.xml'
)

if not launch_path.exists():
    print(f'Warning: CARLA top-LiDAR override skipped; missing {launch_path}')
else:
    backup_path = launch_path.with_suffix(launch_path.suffix + '.ub-original')
    if not backup_path.exists():
        backup_path.write_text(launch_path.read_text())
    text = backup_path.read_text()
    quote = chr(34)
    old = f'<arg name={quote}use_concat_filter{quote} default={quote}true{quote}/>'
    new = f'<arg name={quote}use_concat_filter{quote} default={quote}false{quote}/>'
    if old in text:
        launch_path.write_text(text.replace(old, new, 1))
        print(f'Disabled Autoware multi-LiDAR concat filter for CARLA: {launch_path}')
    elif new in text:
        print(f'Autoware multi-LiDAR concat filter already disabled for CARLA: {launch_path}')
    else:
        print(f'Warning: use_concat_filter default not found in {launch_path}')
PY
  python3 - <<'PY' &
import rclpy
from rclpy.qos import DurabilityPolicy
from rclpy.qos import HistoryPolicy
from rclpy.qos import QoSProfile
from rclpy.qos import ReliabilityPolicy
from sensor_msgs.msg import PointCloud2

SOURCE_TOPIC = '/sensing/lidar/top/pointcloud_before_sync'
OUTPUT_TOPIC = '/sensing/lidar/concatenated/pointcloud'

rclpy.init()
node = rclpy.create_node('ub_carla_top_lidar_relay')
qos = QoSProfile(
    history=HistoryPolicy.KEEP_LAST,
    depth=10,
    reliability=ReliabilityPolicy.BEST_EFFORT,
    durability=DurabilityPolicy.VOLATILE,
)
publisher = node.create_publisher(PointCloud2, OUTPUT_TOPIC, qos)

def relay(message):
    publisher.publish(message)

node.create_subscription(PointCloud2, SOURCE_TOPIC, relay, qos)
node.get_logger().info(f'Relaying {SOURCE_TOPIC} -> {OUTPUT_TOPIC}')
rclpy.spin(node)
PY
  UB_BACKGROUND_PIDS=\"\${UB_BACKGROUND_PIDS} \$!\"
fi
if [[ $(shell_quote "${UB_AUTOWARE_PATCH_CARLA_BRIDGE}") == 1 ]]; then
  python3 - <<'PY'
from pathlib import Path

source_root = Path('/autoware/build/autoware_carla_interface/src/autoware_carla_interface')
carla_ros_path = source_root / 'carla_ros.py'
carla_autoware_path = source_root / 'carla_autoware.py'
quote = chr(34)

def patch_file(path, replacements):
    if not path.exists():
        print(f'Warning: CARLA bridge patch skipped; missing {path}')
        return
    backup = path.with_suffix(path.suffix + '.ub-original')
    if not backup.exists():
        backup.write_text(path.read_text())
    text = backup.read_text()
    changed = False
    for old, new in replacements:
        if new in text:
            continue
        if old not in text:
            print(f'Warning: CARLA bridge patch pattern not found in {path}: {old!r}')
            continue
        text = text.replace(old, new, 1)
        changed = True
    if changed:
        path.write_text(text)
        print(f'Applied CARLA bridge runtime patch: {path}')

patch_file(
    carla_ros_path,
    [
        (
            'from autoware_vehicle_msgs.msg import ControlModeReport\n',
            'from autoware_vehicle_msgs.msg import ControlModeReport\n'
            'from autoware_vehicle_msgs.srv import ControlModeCommand\n',
        ),
        (
            '        self.current_control = carla.VehicleControl()\n',
            '        self.sub_control_mode_override = self.ros2_node.create_subscription(\n'
            '            ControlModeReport, \'/ub/carla/control_mode\', self.control_mode_override_callback, 1\n'
            '        )\n'
            '        self.srv_control_mode = self.ros2_node.create_service(\n'
            '            ControlModeCommand, \'/control/control_mode_request\', self.control_mode_request_callback\n'
            '        )\n'
            '        self.current_control_mode = ControlModeReport.MANUAL\n'
            '        self.current_control = carla.VehicleControl(brake=1.0, hand_brake=True)\n'
            '        self.received_control_cmd = False\n',
        ),
        (
            '    def control_callback(self, in_cmd):\n'
            ,
            '    def control_mode_override_callback(self, msg):\n'
            '        self.current_control_mode = msg.mode\n\n'
            '    def control_mode_request_callback(self, request, response):\n'
            '        # Accept Autoware operation-mode control ownership requests.\n'
            '        if request.mode == ControlModeCommand.Request.AUTONOMOUS:\n'
            '            self.current_control_mode = ControlModeReport.AUTONOMOUS\n'
            '        elif request.mode == ControlModeCommand.Request.MANUAL:\n'
            '            self.current_control_mode = ControlModeReport.MANUAL\n'
            '            self.current_control = carla.VehicleControl(brake=1.0, hand_brake=True)\n'
            '        else:\n'
            '            self.current_control_mode = request.mode\n'
            '        response.success = True\n'
            '        return response\n\n'
            '    def control_callback(self, in_cmd):\n'
        ),
        (
            '        out_cmd = carla.VehicleControl()\n',
            '        if self.current_control_mode != ControlModeReport.AUTONOMOUS:\n'
            '            return\n'
            '        out_cmd = carla.VehicleControl()\n',
        ),
        (
            '        out_cmd.brake = in_cmd.actuation.brake_cmd\n'
            '        self.current_control = out_cmd\n',
            '        out_cmd.brake = in_cmd.actuation.brake_cmd\n'
            '        out_cmd.hand_brake = False\n'
            '        self.received_control_cmd = True\n'
            '        self.current_control = out_cmd\n',
        ),
        (
            f'            ControlModeReport, {quote}/vehicle/status/control_mode{quote}, 1\n',
            f'            ControlModeReport, {quote}/ub/carla/status/control_mode_raw{quote}, 1\n',
        ),
        (
            '        out_ctrl_mode.stamp = out_vel_state.header.stamp\n'
            '        out_ctrl_mode.mode = ControlModeReport.AUTONOMOUS\n',
            '        out_ctrl_mode.stamp = out_vel_state.header.stamp\n'
            '        out_ctrl_mode.mode = self.current_control_mode\n',
        ),
    ],
)

patch_file(
    carla_autoware_path,
    [
        (
            '        self.interface.physics_control = self.ego_actor.get_physics_control()\n\n'
            '        self.sensor_wrapper = SensorWrapper(self.interface)\n',
            '        self.interface.physics_control = self.ego_actor.get_physics_control()\n'
            '        self.ego_actor.set_target_velocity(carla.Vector3D(0.0, 0.0, 0.0))\n'
            '        self.ego_actor.set_target_angular_velocity(carla.Vector3D(0.0, 0.0, 0.0))\n'
            '        self.ego_actor.apply_control(carla.VehicleControl(brake=1.0, hand_brake=True))\n\n'
            '        self.sensor_wrapper = SensorWrapper(self.interface)\n',
        ),
    ],
)
PY
fi
if [[ $(shell_quote "${UB_AUTOWARE_EGO_ONLY_PERCEPTION}") == 1 ]]; then
  python3 - <<'PY'
from pathlib import Path

path = Path('/autoware/install/autoware_launch/share/autoware_launch/launch/autoware.launch.xml')
if not path.exists():
    print(f'Warning: ego-only perception patch skipped; missing {path}')
else:
    backup = path.with_suffix(path.suffix + '.ub-original')
    if not backup.exists():
        backup.write_text(path.read_text())
    text = backup.read_text()
    quote = chr(34)
    dollar = chr(36)
    data_path_arg = (
        f'      <arg name={quote}data_path{quote} '
        f'value={quote}{dollar}(var data_path){quote}/>\n'
    )
    empty_objects_arg = (
        f'      <arg name={quote}use_empty_dynamic_object_publisher{quote} '
        f'value={quote}true{quote}/>\n'
    )
    if empty_objects_arg in text:
        path.write_text(text)
        print(f'Ego-only empty object publisher already enabled: {path}')
    elif data_path_arg in text:
        path.write_text(text.replace(data_path_arg, data_path_arg + empty_objects_arg, 1))
        print(f'Enabled ego-only empty object publisher: {path}')
    else:
        print(f'Warning: perception include data_path arg not found in {path}')
PY
fi
python3 - <<'PY' &
import rclpy
from autoware_vehicle_msgs.msg import ControlModeReport
from autoware_vehicle_msgs.srv import ControlModeCommand
from tier4_system_msgs.msg import OperationModeAvailability

rclpy.init()
node = rclpy.create_node('ub_carla_control_mode_shim')
mode = ControlModeReport.MANUAL
status_pub = node.create_publisher(ControlModeReport, '/vehicle/status/control_mode', 1)
override_pub = node.create_publisher(ControlModeReport, '/ub/carla/control_mode', 1)
availability_pub = node.create_publisher(
    OperationModeAvailability, '/system/operation_mode/availability', 1
)

def publish_mode():
    msg = ControlModeReport()
    msg.stamp = node.get_clock().now().to_msg()
    msg.mode = mode
    status_pub.publish(msg)
    override_pub.publish(msg)

    availability = OperationModeAvailability()
    availability.stamp = msg.stamp
    availability.stop = True
    availability.autonomous = True
    availability.local = True
    availability.remote = True
    availability.emergency_stop = True
    availability.comfortable_stop = False
    availability.pull_over = False
    availability_pub.publish(availability)

def on_request(request, response):
    global mode
    if request.mode == ControlModeCommand.Request.AUTONOMOUS:
        mode = ControlModeReport.AUTONOMOUS
    elif request.mode == ControlModeCommand.Request.MANUAL:
        mode = ControlModeReport.MANUAL
    else:
        mode = request.mode
    publish_mode()
    response.success = True
    return response

node.create_service(ControlModeCommand, '/control/control_mode_request', on_request)
node.create_timer(0.05, publish_mode)
node.get_logger().info(
    'Providing /control/control_mode_request, /vehicle/status/control_mode, '
    'and simulator operation-mode availability'
)
rclpy.spin(node)
PY
UB_BACKGROUND_PIDS=\"\${UB_BACKGROUND_PIDS} \$!\"
trap 'for pid in \${UB_BACKGROUND_PIDS:-}; do kill \${pid} 2>/dev/null || true; done' EXIT
ros2 launch autoware_launch e2e_simulator.launch.xml \\
  map_path:=$(shell_quote "${AUTOWARE_MAP_PATH}") \\
  vehicle_model:=$(shell_quote "${AUTOWARE_VEHICLE_MODEL}") \\
  sensor_model:=$(shell_quote "${AUTOWARE_SENSOR_MODEL}") \\
  simulator_type:=carla \\
  host:=$(shell_quote "${AUTOWARE_CARLA_HOST}") \\
  carla_map:=$(shell_quote "${CARLA_MAP}")
"

  echo "Launching Autoware. Press Ctrl+C to stop the ROS launch."
  docker compose "${exec_args[@]}" "${AUTOWARE_SERVICE}" bash -lc "${launch_cmd}"
}

for arg in "$@"; do
  case "${arg}" in
    --dry-run)
      DRY_RUN=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run_preflight

if [[ "${DRY_RUN}" -eq 1 ]]; then
  print_dry_run
  exit 0
fi

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start_carla
launch_autoware
