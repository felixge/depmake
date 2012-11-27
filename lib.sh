#!/bin/bash

# Stop on errors or when encountering unset variables being references
set -eu

# Conventions:
#
# * private methods start with '_dm_' ('dm' stands for depmake)
# * public functions start with 'dm_'


###################
# Private methods #
###################

_dm_packet_file() {
  local packet=${1}
  echo ${DM_PACKETS_DIR}/${packet}.sh
}

_dm_build_dir() {
  local packet=${1}
  echo ${DM_BUILD_DIR}/${packet}
}

dm_sha1() {
  openssl sha1 ${1} | cut -d ' ' -f 2
}

_dm_verify_sha1() {
  local path=${1}
  local expected_sha1=${2}

  if [[ ! -f "${path}" ]]; then
    echo "Error: cannot verify sha1 for non-existing file: ${path}"
    return 1
  fi

  local actual_sha1=`dm_sha1 ${path}`

  if [ "${actual_sha1}" != "${expected_sha1}" ]; then
    echo "Error: expected sha1: ${expected_sha1}, but got: ${actual_sha1} for ${path}"
    return 1
  fi
}

_dm_verify_fingerprint() {
  local packet=${1}
  local deps=${@:2}

  expected_fingerprint=`_dm_calculate_fingerprint ${packet} ${deps}`
  actual_fingerprint=`_dm_read_fingerprint ${packet}`

  if [ "${actual_fingerprint}" != "${expected_fingerprint}" ]; then
    return 1
  fi
}

_dm_calculate_fingerprint() {
  local packet=${1}
  local deps=${@:2}
  local packet_file=`_dm_packet_file ${packet}`
  local packet_fingerprint="${packet}-`dm_sha1 ${packet_file}`"

  local dep_fingerprints=""
  for dep in ${deps[@]}
  do
    local dep_fingerprint=`_dm_read_fingerprint ${dep}`
    dep_fingerprints="${dep_fingerprints}:${dep_fingerprint}"
  done

  local packet_custom_fingerprint=""
  if type fingerprint >/dev/null 2>&1; then
    packet_custom_fingerprint=":`fingerprint`"
  fi

  echo "${packet_fingerprint}${packet_custom_fingerprint}${dep_fingerprints}"
}

_dm_read_fingerprint() {
  local packet=${1}
  cat `_dm_fingerprint_path ${packet}`
}

_dm_fingerprint_path() {
  local packet=${1}
  echo "`_dm_build_dir ${packet}`/build.fingerprint"
}

_dm_write_fingerprint() {
  local packet=${1}
  local deps=${@:2}

  local fingerprint_path=`_dm_fingerprint_path ${packet}`
  local fingerprint=`_dm_calculate_fingerprint ${packet} ${deps}`

  echo ${fingerprint} > ${fingerprint_path}
}

##################
# Public methods #
##################
dm_build() {
  local packet=${1}
  local deps=${@:2}

  local packet_file=`_dm_packet_file ${packet}`
  local build_dir=`_dm_build_dir ${packet}`

  source ${packet_file}

  echo "========== Building ${packet} =========="

  if _dm_verify_fingerprint ${packet} ${deps}; then
    echo "Not rebuilding, fingerprint is current."
  else
    mkdir -p ${build_dir}
    cd ${build_dir}
    time build ${DM_STACK_DIR}
    _dm_write_fingerprint ${packet} ${deps}
  fi
}

dm_download_file() {
  local filename=${1}
  local url=${2}
  local sha1=${3}

  if _dm_verify_sha1 ${filename} ${sha1}; then
    echo "Sha1 for ${filename} matches, no need to re-download"
    return 0
  fi

  echo "Downloading ${filename} from ${url} ..."
  curl --fail -L -o ${filename} ${url}

  _dm_verify_sha1 ${filename} ${sha1}
}

dm_download_git() {
  local repo=${1}
  local ref=${2}
  local clone_dir=${3}

  code=`cd ${clone_dir} && git reset ${ref} -q --hard; echo $?`
  if [ ${code} -eq 0 ]; then
    return 0
  fi

  code=`cd ${clone_dir} && git fetch && git reset ${ref} -q --hard; echo $?`
  if [ ${code} -eq 0 ]; then
    return 0
  fi

  rm -rf ${clone_dir}
  git clone ${repo} ${clone_dir}
  ( cd ${clone_dir} && git reset ${ref} -q --hard )
}

dm_download_svn() {
  local repo=${1}
  local ref=${2}
  local checkout_dir=${3}

  svn checkout -r ${ref} ${repo} ${checkout_dir}
}
