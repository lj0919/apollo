#! /usr/bin/env bash

###############################################################################
# Copyright 2020 The Apollo Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

TARGET_DIR="${TOP_DIR}/sensor_calibration"
TEMPLATE_DIR="${TOP_DIR}/docs/Apollo_Fuel/examples/sensor_calibration"
DEFAULT_RECORD_DIR="${TOP_DIR}/data/bag"

NO_INTERACTIVE=0

TASK=""
VALID_TASKS=("lidar_to_gnss" "camera_6mm_to_lidar" "camera_12mm_to_lidar")

RECORD_FILES=()
RECORD_DIRS=()

function join_by() {
  local d=$1
  shift
  echo -n "$1"
  shift
  printf "%s" "${@/#/$d}"
}

function print_usage() {
  echo "Usage:
    ./extract_data.sh -t [ $(join_by ' | ' ${VALID_TASKS[@]}) ] -f <path/to/record/file> -d <path/to/record/dir>
  eg.
    ./extract_data.sh -t lidar_to_gnss -f xxx/yyy.record.00000 -f xxx/yyy.record.00001
  or
    ./extract_data.sh -t camera_6mm_to_lidar -d xxx
  "
}

function parse_args() {
  # read options
  while getopts ':t:f:d:n' flag; do
    case "${flag}" in
      t)
        TASK="${OPTARG}"
        ;;
      f)
        RECORD_FILES+=("${OPTARG}")
        ;;
      d)
        RECORD_DIRS+=("${OPTARG}")
        ;;
      n)
        NO_INTERACTIVE=1
        ;;
      *)
        print_usage
        exit 1
        ;;
    esac
  done

  if [[ " ${VALID_TASKS[@]} " =~ " ${TASK} " ]]; then
    TARGET_DIR="${TARGET_DIR}/${TASK}"
    TEMPLATE_DIR="${TEMPLATE_DIR}/${TASK}"
  else
    print_usage
    exit 1
  fi
}

function check_target_dir() {
  if [[ ! -d "${TARGET_DIR}" ]]; then
    mkdir -p ${TARGET_DIR}
    cp -R ${TEMPLATE_DIR}/* ${TARGET_DIR}
  elif [[ ! -z "$(ls -A ${TARGET_DIR})" ]]; then
    if [[ "${NO_INTERACTIVE}" -eq 0 ]]; then
      local warn="The ${TARGET_DIR} is not empty, do you want to delete it? (Y/n)"
      echo "${warn}"
      local answer
      typeset -l answer && read answer
      if [ "${answer}" == "y" ]; then
        rm -rf ${TARGET_DIR}/*
      fi
    else
      rm -rf ${TARGET_DIR}/*
    fi
    cp -R ${TEMPLATE_DIR}/* ${TARGET_DIR}
  else
    cp -R ${TEMPLATE_DIR}/* ${TARGET_DIR}
  fi
}

# Since pypcd installed via `pip install` only works with python2.7,
# we can only install it this way
function _install_pypcd() {
  git clone https://github.com/dimatura/pypcd --depth=1
  pushd pypcd >/dev/null
  git fetch origin pull/9/head:python3 && git checkout python3
  python3 setup.py install --user
  popd >/dev/null
  rm -rf pypcd
}

function _get_latest() {
  local parent_dir=$1
  local latest=$(ls -lt ${parent_dir} | grep -v '_s' |
    grep -m1 '^d' | awk '{print $NF}')
  if [[ -z "${latest}" ]]; then
    echo "There is no reord directories in ${parent_dir}!"
    exit 1
  else
    echo "${parent_dir}/${latest}"
  fi
}

function get_records() {
  if [[ ${#RECORD_FILES[*]} -eq 0 && ${#RECORD_DIRS[*]} -eq 0 ]]; then
    RECORD_DIRS+=($(_get_latest ${DEFAULT_RECORD_DIR}))
  fi

  local tmp_file="${TARGET_DIR}/tmp.txt"

  for file in "${RECORD_FILES[@]}"; do
    if [[ -f "${file}" ]]; then
      if [[ "${file}" == *"record"* ]]; then
        echo '  record_path: "'$(readlink -f ${file})'"' >>"${tmp_file}"
        sed -i "/# records can be specified as a list/r ${tmp_file}" "${TARGET_DIR}/lidar_to_gnss.config"
      else
        echo "The input file ${file} is not a record!"
        exit 1
      fi
    else
      echo "File ${file} doesn't exist!"
      exit 1
    fi
  done
  rm -f ${tmp_file}

  for dir in "${RECORD_DIRS[@]}"; do
    if [[ -d "${dir}" ]]; then
      if [[ -z "$(ls ${dir} | grep record)" ]]; then
        echo "There is no reord file in ${dir}!"
        exit 1
      fi
      echo '  record_path: "'$(readlink -f ${dir})'"' >>"${tmp_file}"
      sed -i "/# or, records can be loaded from a directory/r ${tmp_file}" "${TARGET_DIR}/lidar_to_gnss.config"
    else
      echo "Directory ${dir} doesn't exist!"
      exit 1
    fi
  done
  rm -f ${tmp_file}
}

function install_if_not_exist() {
  while [[ $# -gt 0 ]]; do
    local pkg=$1
    shift
    pip show --files "${pkg}" >/dev/null
    if [[ $? -ne 0 ]]; then
      if [[ "${pkg}" == "pypcd" ]]; then
        _install_pypcd
      else
        sudo pip install --no-cache-dir "${pkg}"
      fi
    fi
  done
}

function update_lidar_config() {
  local record
  local lidar_channels
  local tmp_file="${TARGET_DIR}/tmp.txt"
  local channel_template="${TEMPLATE_DIR}/channel_template.txt"
  local extraction_rate="5"
  if [[ ${#RECORD_FILES[*]} -ne 0 ]]; then
    record="$(readlink -f ${RECORD_FILES[0]})"
  else
    record="$(readlink -f ${RECORD_DIRS[0]})/$(ls ${RECORD_DIRS[0]} | grep -m1 record)"
  fi
  lidar_channels=($(cyber_recorder info ${record} | awk '{print $1}' |
    grep PointCloud2 | grep -v "fusion" | grep -v "compensator"))

  if [ "${#lidar_channels[*]}" -eq 0 ]; then
    echo "There is no PointCloud messages in ${record}, please check your record!"
    exit 1
  fi

  sed -i "s|__RATE__|${extraction_rate}|g" "${channel_template}"
  for channel in "${lidar_channels[@]}"; do
    sed -i "s|__NAME__|${channel}|g" "${channel_template}"
    cat "${channel_template}" >>"${tmp_file}"
    sed -i "s|${channel}|__NAME__|g" "${channel_template}"
  done
  sed -i "s|${extraction_rate}|__RATE__|g" "${channel_template}"

  sed -i "/# channel of mulitple lidars/{n;N;N;N;N;d}" "${TARGET_DIR}/lidar_to_gnss.config"
  sed -i "/# channel of mulitple lidars/r ${tmp_file}" "${TARGET_DIR}/lidar_to_gnss.config"
  rm -f ${tmp_file}
}

function main() {
  parse_args "$@"
  check_target_dir
  get_records
  if [[ "${TASK}" == "lidar_to_gnss" ]]; then
    update_lidar_config
  fi
  install_if_not_exist "pyyaml" "pypcd"

  local extract_data_bin="${TOP_DIR}/bazel-bin/modules/tools/sensor_calibration/extract_data"
  if [[ -f "${extract_data_bin}" ]]; then
    "${extract_data_bin}" --config "${TARGET_DIR}/${TASK}.config"
  else
    bazel run //modules/tools/sensor_calibration:extract_data \
      -- --config "${TARGET_DIR}/${TASK}.config"
  fi

  local sanity_check_bin="${TOP_DIR}/bazel-bin/modules/tools/sensor_calibration/sanity_check"
  if [[ -f "${sanity_check_bin}" ]]; then
    "${sanity_check_bin}" --input_folder ${TARGET_DIR}/extracted_data
  else
    bazel run //modules/tools/sensor_calibration:sanity_check \
      -- --input_folder ${TARGET_DIR}/extracted_data
  fi

  rm -f ${TARGET_DIR}/records/*
}

main "$@"
