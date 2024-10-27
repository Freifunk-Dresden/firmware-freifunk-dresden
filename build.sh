#!/bin/bash
# Copyright (C) 2006 - present, Stephan Enderlein<stephan@freifunk-dresden.de
# GNU General Public License Version 3

#usage: see below
SCRIPT_VERSION="2.25"


# gitlab variables
# FF_REGISTERKEY_PREFIX
# FF_BUILD_TAG
# FF_MESH_KEY

# check terms
case "$TERM" in
  xterm*) _TERM=1 ;;
  screen) _TERM=1 ;;
  vt1*)   _TERM=1 ;;
  *) _TERM=0 ;;
esac


# target file
PLATFORMS_JSON="build.json"

USE_DOCKER=false
DOCKER_IMAGE="freifunkdresden/openwrt-docker-build"
DOCKER_FINAL_TGZ="docker-final-output.tgz"
DOCKER_CONTAINER_NAME="ffbuild"

DL_DIR=dl
WORK_DIR=workdir
FINAL_OUTPUT_DIR="final_output"	# used by gen-upload.sh (docker)
LOCAL_OUTPUT_DIR="_output"			# location to copy images/packages to, after each targets
CONFIG_DIR=fw-configs
CONFIG_DEFAULT_FILE="default.config"
OPENWRT_PATCHES_DIR=fw-patches
DDMESH_STATUS_DIR=".ddmesh"	# used to store build infos like openwrt_patches_target states
DDMESH_PATCH_STATUS_DIR="$DDMESH_STATUS_DIR/patches-applied"
COMPILE_STATUS_DIR=".compile-status"
COMPILE_STATUS_FILE_SUFFIX="compile-status.json"

# -------------------------------------------------------------------

#Black        0;30     Dark Gray     1;30
#Red          0;31     Light Red     1;31
#Green        0;32     Light Green   1;32
#Brown/Orange 0;33     Yellow        1;33
#Blue         0;34     Light Blue    1;34
#Purple       0;35     Light Purple  1;35
#Cyan         0;36     Light Cyan    1;36
#Light Gray   0;37     White         1;37
# 0 normal
# 1 highlight
# 2 darker
# 3 kursiv
# 4
# 5 blink
# 7 swap background/foreground
# 8 fg/bg same color
# 9 strike

C_NONE='\033[0m' # No Color
C_GREY='\033[1;30m'
C_RED='\033[0;31m'
C_LRED='\033[1;31m'
C_GREEN='\033[0;32m'
C_LGREEN='\033[1;32m'
C_ORANGE='\033[0;33m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_LBLUE='\033[1;34m'
C_PURPLE='\033[0;35m'
C_LPURPLE='\033[1;35m'
C_CYAN='\033[0;36m'
C_LCYAN='\033[1;36m'
C_GREY='\033[0;37m'
C_LGREY='\033[1;37m'
C_BLINK='\033[5m'
BG_BLACK='\033[40m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_PURBLE='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'

# MARK_OK='+'
# MARK_FAIL='E'
# MARK_BLINK='*'
# MARK_NONE=' '
MARK_OK='✔'
MARK_FAIL='✘'
MARK_BLINK='➤'
MARK_NONE=' '
MARK_SKIP='-'
MARK_IGNORE='i'
MARK_DISABLED='/'

if true; then
  PBC_RUNNING="${C_YELLOW}${C_BLINK}${MARK_BLINK}${C_NONE}"
  PBC_ERROR="${C_LRED}${MARK_FAIL}${C_NONE}"
  PBC_IGNORE="${C_RED}${MARK_IGNORE}${C_NONE}"
  PBC_DISABLED="${C_LPURPLE}${MARK_DISABLED}${C_NONE}"
  PBC_SUCCESS="${C_GREEN}${MARK_OK}${C_NONE}"
  PBC_SKIP="${C_GREEN}${MARK_SKIP}${C_NONE}"
  PBC_SPACE="${MARK_NONE}"
else
  PBC_RUNNING="${MARK_BLINK}"
  PBC_ERROR="${MARK_FAIL}"
  PBC_IGNORE="${MARK_IGNORE}"
  PBC_DISABLED="${MARK_DISABLED}"
  PBC_SUCCESS="${MARK_OK}"
  PBC_SKIP="${MARK_SKIP}"
  PBC_SPACE="${MARK_NONE}"
fi

# define color lookup table used when displaying targets via "list"
declare -A list_color
list_color['18.06']="${BG_BLACK}"
list_color['21.02']="${BG_BLACK}"
list_color['22.03']="${BG_BLUE}"
list_color['23.05.3']="${BG_PURBLE}"
list_color['8.2.6']="${BG_BLUE}"
list_color['9.0.0']="${BG_PURBLE}"

#printf "${list_color['18.06']}aaa ${list_color['21.02']}%s ${C_NONE}bbb\n" "value"
#printf "${list_color[$v]}aaa ${list_color['21.02']}%s ${C_NONE}bbb\n" "value"

# explicitly create an assotiative array that holds extracted template
# values for each template
declare -A configTemplateValues


#save current directory when copying config file
RUN_DIR=$(pwd)

global_error=0

###--------------------------------- functions -----------------------------------------------------



setup_buildroot ()
{
 buildroot=$1
 openwrt_rev=$2
 openwrt_dl_dir=$3
 openwrt_patches_dir=$4
 firmware_files=$5

 openwrt_dl_tgz="$openwrt_dl_dir/openwrt-$openwrt_rev.tgz"

 git_url="https://git.openwrt.org/openwrt/openwrt.git"

  # check if directory exists. I'm not just checking
  # the build root itself, because gitlab left a working directory
  # only with freifunk files, but without all other openwrt files
  if [ ! -d "$buildroot/toolchain" ]
  then
    echo "directory [$buildroot/toolchain] not present -> re-create '$buildroot'"
    # ensure we have a clean workdir, after gitlab runner had removed
    # openwrt.org files (e.g. toolchain)
    rm -rf "$buildroot"

    # re-create buildroot
    mkdir -p "$buildroot"
    if [ ! -d "$buildroot" ]; then
      echo "Error: '$buildroot' could not be created. exit."
      clean_up_exit 1
    fi

    #check if we have already downloaded the openwrt revision
    if [ -f $openwrt_dl_tgz ]
    then
      #extract into buildroot dir
      echo "using already downloaded $openwrt_dl_tgz"
      cd $buildroot
      tar xzf $RUN_DIR/$openwrt_dl_tgz
    else
      #clone from openwrt
      echo "cloning openwrt"
      git clone $git_url $buildroot
      echo "switch to specific revision"
      cd $buildroot
      git checkout $openwrt_rev >/dev/null
      echo "create openwrt tgz"
      tar czf $RUN_DIR/$openwrt_dl_tgz .
    fi
    cd $RUN_DIR

    #apply openwrt patches
    if [ -d $openwrt_patches_dir ]; then
      for i in $openwrt_patches_dir/*.patch
      do
        echo -e "${C_CYAN}apply openwrt patch:${C_NONE} $i to buildroot:$buildroot"
        # --no-backup-if-mismatch avoids creating backup files for files
        # with different names or if not exist (new files)
        patch --no-backup-if-mismatch --directory=$buildroot -p1 < $i
      done
    fi
  else
    echo -e "${C_CYAN}Buildroot [$buildroot]${C_NONE} already present"
  fi

  echo -n -e $C_CYAN"create dl directory/links"$C_NONE": "
  rm -f $buildroot/dl
  ln -s ../../$openwrt_dl_dir $buildroot/dl
  echo "done."

  # ---------------------------------
  # 1. copy 'common' files that are independent of openwrt version
  # 2. copy all version specific files. this will overwrite existing files the came from 'common'
  # 3. delete files that should be remove.
  #    Note: files that should be deleted, should end with '~'. for instance, when
  #    '/www/admin/iptables.cgi' from common is should not present in specific version,
  #    then create an empty file '/www/admin/iptables.cgi~'
  #    this file will then be removed from specific version
  #
  # -------- common files -----------
  # copy common files first
    rm -rf $buildroot/files
  mkdir -p $buildroot/files

	# check for common symlink
	common_dir="$RUN_DIR/fw-files/${firmware_files}.common"
	if [ -L "${common_dir}" ]; then
	  echo -n -e "${C_CYAN}copy rootfs (${common_dir})${C_NONE}: "
		# remove-destination forces copy (first remove existing file (e.g. symlinks))
		cp -a --remove-destination ${common_dir}/* $buildroot/files/
		echo " done."
	else
	  echo -e "${C_CYAN}No rootfs to copy: (${common_dir})${C_NONE}"
	fi


  # -------- specific files -----------
  # copy specific files over (may overwrite common)
  echo -n -e "${C_CYAN}copy specific files ${C_NONE} [${C_GREEN}${firmware_files}${C_NONE}]: "
  if [ -n "${firmware_files}" -a -d "$RUN_DIR/fw-files/${firmware_files}" ]; then
    # --remove-destination forces copy (first remove existing file (e.g. symlinks))
    cp -a --remove-destination $RUN_DIR/fw-files/${firmware_files}/* $buildroot/files/
    echo "done."

    echo -n -e "${C_CYAN}removing unwanted files/directories ${C_NONE} [${C_GREEN}${firmware_files}${C_NONE}]: "
    find $buildroot/files/ -name '*~' -exec sh -c 'f="{}"; rm -rf "$f" "${f%*~}"' \; 2>/dev/null
    echo "done."
  else
    echo "no specific files."
  fi

  echo -n -e $C_CYAN"create rootfs/etc/built_info file: "$C_NONE
  mkdir -p $buildroot/files/etc
  > $buildroot/files/etc/built_info
  echo "done."

  # more dynamic changes
  echo -n -e $C_CYAN"setup dynamic firmware config: "$C_NONE
  setup_dynamic_firmware_config "$buildroot/files" || { echo "ERROR"; exit 1;}
  echo "done."

  echo "----- generate built_info ----"
  git_openwrt_rev=$(cd $buildroot && git log -1 --format=%H)
  git_openwrt_branch=$(cd $buildroot && git name-rev --name-only $git_openwrt_rev | sed 's#.*/##')
  echo "git_openwrt_rev:$git_openwrt_rev" >> $buildroot/files/etc/built_info
  echo "git_openwrt_branch:$git_openwrt_branch" >> $buildroot/files/etc/built_info

  # when running from gitlab only specific revision is cloned. there are no branch infos.
  # So I check if FF_BUILD_TAG is set and then use this. If not defined I use
  # the one I can determine.
  git_ddmesh_rev="$(git log -1 --format=%H)"
  if [ -n "$FF_BUILD_TAG" ]; then
    git_ddmesh_branch="$FF_BUILD_TAG"
  else
    git_ddmesh_branch="$(git name-rev --tags --name-only $git_ddmesh_rev | sed 's#.*/##')"

    if [ "$git_ddmesh_branch" = "undefined" ]; then
      git_ddmesh_branch="$(git branch | sed -n 's#^\* \(.*\)#\1#p')"
      echo ""
      echo -e $C_RED"WARNING: building from UN-TAGGED (git) sources"$C_NONE
      echo ""
      sleep 5
    fi
  fi

  echo "git_ddmesh_rev:$git_ddmesh_rev" >> $buildroot/files/etc/built_info
  echo "git_ddmesh_branch:$git_ddmesh_branch" >> $buildroot/files/etc/built_info
  echo "builtdate:$(date +'%H:%M:%S / %d %h %y')" >> $buildroot/files/etc/built_info

  echo "git_openwrt_rev:     $git_openwrt_rev"
  echo "git_openwrt_branch:  $git_openwrt_branch"
  echo "git_ddmesh_rev:      $git_ddmesh_rev"
  echo "git_ddmesh_branch:   $git_ddmesh_branch"
  echo ""


} # setup_buildroot

# status:
#  0 - success
#  1 - error
#  2 - compiling
write_compile_status()
{
  local config="$1"
  local status="$2"
  local file="$3"
  mkdir -p $(dirname $file)
  test "$status" = "0" && d="$(date +'%H:%M:%S / %d %h %y' | sed 's#Mär#Mar#')" || d=""
  echo "{\"config\":\"${config}\", \"date\":\"$d\", \"status\":\"${status}\"}" > "${file}"
}


progressbar()
{
  _value=$1
  shift
  _maxValue=$1
  shift
  _marker=$1
  shift
  _char_array=("$@")	# get all other strings and create array again

  if [ "$_TERM" = "1" -a -n "$_value" -a -n "$_maxValue" ]; then
    # get current number of terminal colums
    cols=$(tput cols)

    title="Progress: "
    title_len=${#title}	# title length

    let _progress=(${_value}*100/${_maxValue})
    progress_string="$(printf ' %3u%% (%u/%u)' $_progress $_value $_maxValue )"
    progress_strlen=${#progress_string}

    # calulate length of bar
    len=$(( cols - title_len - 2 - progress_strlen))

    charsPerValue=$(( len / _maxValue))
    # make len multiple of charsPerValue
    len=$(( charsPerValue * _maxValue))
    charSteps=$((len / charsPerValue))


    # reduce len by number of _maxValue, because
    # marker are inserted into _bar which makes it
    # longer again.
    # consider length marker string
    if [ -n "${_marker}" ]; then
      len=$((len - (charSteps*${#_marker})))
      charsPerValue=$((charsPerValue-${#_marker}))
    fi
    absCharPos=$((charsPerValue * _value))


    _bar=""
    pos=0
    nextMarkerPos=$charsPerValue
    barCharIdx=0
    while [ $pos -lt $len ]
    do
      pos=$((pos + 1))

      if [ $pos -le $absCharPos ]; then
        _bar="${_bar}${_char_array[$barCharIdx]}"
      else
        _bar="${_bar}${PBC_SPACE}"
      fi

      [ $pos -ge $len ] && break;

      if [ -n "${_marker}" -a $pos -eq $nextMarkerPos ]; then
        _bar="${_bar}${_marker}"
        nextMarkerPos=$(( nextMarkerPos + charsPerValue))
        barCharIdx=$((barCharIdx +1 ))
      fi
    done


    # construct complete bar
    #printf "%s[%s]%s" "${title}" "${_bar}" "${progress_string}"
    echo -e -n "${title}[${_bar}]${progress_string}"

    # clear until end of line
    tput el
  fi
}

# clean up screen and
clean_up_exit()
{
  EXIT="$1"
  if [ "$_TERM" = "1" ]; then
    # reset region
    if [ -n "$row" ]; then
      printf "\\033[r\n"
      tput cup $row 0
      printf "\n"
    fi
  fi
  exit ${EXIT:=0}
}


show_progress()
{
  if [ "$_TERM" = "1" ]; then
    target="$1"
    shift

    # dont overwrite last value, when no parameter was given (window resize signal)
    [ -n "$1" ] && _count=$1
    shift
    [ -n "$1" ] && _max=$1
    shift
    [ -n "$1" ] && _bar_char_array=("$@")	# get all other strings and create array again

    [ -z "$_count" ] && return
    [ -z "$_max" -o "$_max" -eq 0 ] && return

    # get current number of lines from (terminal size)
    row=$(tput lines)

    # empty second line of terminal (top)
    tput cup 1 0
    tput el

    # print progress bar at bottom
    tput cup $(( $row - 1)) 0
    progressbar $_count $_max "|" "${_bar_char_array[@]}"		# pass last array as separate parameters
                                                            # but as one argument with "" to allow
                                                            # special characters like *

    # print current target
    tput cup $(( $row - 2)) 0
    tput el
    echo -e "building: $C_BLUE${target}$C_NONE"

    # print empty line above
    tput cup $(( $row - 3)) 0
    tput el

    # define scroll region before setting cursor. else it would overwrite progress bar
    # leave out second row parameter to use max
    printf "\\033[0;%dr" $(( $row - 2 ))

    # set cursor into last line of region
    tput cup $(( $row - 3)) 0
  fi
}



############# build.sh functions ####################

getTargetsJson()
{
cat $RUN_DIR/$PLATFORMS_JSON | sed -n '
# delete comments (# must not be used anywhere)
s/#.*//
# delete lines starting with //
s#^[ 	]*//.*##

# delete empty lines
# delete leading and tailing spaces
s/^[ 	]*//
s/[ 	]*$//
/^$/d
p
' | jq "[ .targets[] ] | sort_by(.name) "
}

# runs through "cleanJson" to create env variables for each template.
# this is to optimizes resolving configs in resolveConfigValues
# It creates an array of template variables associated with the template names
resolveTemplates()
{
  OPT="--raw-output" # do not excape values

  targetIdx=0
  while true
  do
    entry=$(echo "$cleanJson" | jq ".[$targetIdx]")
    targetIdx=$(( targetIdx + 1 ))

    if [ "$entry" = "null" ]; then
      break
    fi

    # extract feeds and packages separately to keep quotes
    x='"_cfg_type=\"\(.type)\";
        _cfg_template=\"\(.template)\";
        _cfg_name=\"\(.name)\";
        _cfg_file=\"\(.config)\";
        _cfg_disabled=\"\(.disabled)\";
        _cfg_openwrt_rev=\"\(.openwrt_rev)\";
        _cfg_openwrt_variant=\"\(.openwrt_variant)\";
        _cfg_selector_config=\"\(.["selector-config"])\";
        _cfg_selector_feeds=\"\(.["selector-feeds"])\";
        _cfg_selector_files=\"\(.["selector-files"])\";
        _cfg_selector_patches=\"\(.["selector-patches"])\""'
    eval $(echo "$entry" | jq $OPT "$x")

    # is template
    if [ "$_cfg_type" = "template" ]; then
    #echo "XXX:$x"
    #echo $entry | jq  "$x"
      configTemplateValues["${_cfg_name}_config_disabled"]="${_cfg_disabled}"

      configTemplateValues["${_cfg_name}_config_selector_config"]="${_cfg_selector_config}"
      configTemplateValues["${_cfg_name}_config_selector_files"]="${_cfg_selector_files}"
      configTemplateValues["${_cfg_name}_config_selector_feeds"]="${_cfg_selector_feeds}"
      configTemplateValues["${_cfg_name}_config_selector_patches"]="${_cfg_selector_patches}"
      configTemplateValues["${_cfg_name}_config_openwrt_rev"]="${_cfg_openwrt_rev}"
      configTemplateValues["${_cfg_name}_config_openwrt_variant"]="${_cfg_openwrt_variant}"

      # feeds and packages are still json and I have to "jq" those manually to keep quotes
      configTemplateValues["${_cfg_name}_config_feeds"]="$(echo "$entry" | jq $OPT '.feeds')"
      configTemplateValues["${_cfg_name}_config_packages"]="$(echo "$entry" | jq $OPT '.packages')"
    fi
  done
  #echo "${_cfg_name["${_cfg_template}_config_feeds"]}"
  #echo "${_cfg_name["${_cfg_template}_config_packages"]}"
}

# gets a config entry and resolves the referenced template.
# it  sets the environment variables
#
# returns:
#   0 - success
#   1 - function argument error / might be use to detect last entry in a loop
#   2 - config is a template /let ignore templates in a loop
#   3 - incomplete configuration/template
resolveConfigValues()
{
  targetConfigJson="$1"

  OPT="--raw-output" # do not excape values

  if [ "$targetConfigJson" = "null" -o -z "$targetConfigJson" ]; then
    return 1;
  fi

  # create env variables and parse with one call to jq (it is faster than repeatly call it)
  x='"_cfg_type=\"\(.type)\";
      _cfg_template=\"\(.template)\";
      _cfg_name=\"\(.name)\";
      _cfg_file=\"\(.config)\";
      _cfg_disabled=\"\(.disabled)\";
      _cfg_openwrt_rev=\"\(.openwrt_rev)\";
      _cfg_openwrt_variant=\"\(.openwrt_variant)\";
      _cfg_selector_config=\"\(.["selector-config"])\";
      _cfg_selector_feeds=\"\(.["selector-feeds"])\";
      _cfg_selector_files=\"\(.["selector-files"])\";
      _cfg_selector_patches=\"\(.["selector-patches"])\"
    "'
  eval $(echo "$targetConfigJson" | jq $OPT "$x")

  # feeds and packages are still json and I have to "jq" those manually to keep quotes
  _cfg_feeds="$(echo "$targetConfigJson" | jq $OPT '.feeds')"
  _cfg_packages="$(echo "$targetConfigJson" | jq $OPT '.packages')"

  # echo " "
  # echo "name:[$_cfg_name]"
  # echo "type:[$_cfg_type]"
  # echo "template_name:[$_cfg_template]"
  # echo "file:[$_cfg_file]"
  # echo "disabled:[$_cfg_disabled]"

  # check that config and templates have a name
  if [ -z "${_cfg_name}" ]; then
    echo "error: configuration/template has no name"
    return 3
  fi

  # ignore templates
  if [ "${_cfg_type}" = "template" ]; then
    return 2
  fi

  # 2. extract template if specified and set defaults if config has not explictly set values
  if [ "${_cfg_template}" != "null" ]; then

    test "$_cfg_disabled" = "null" && _cfg_disabled="${configTemplateValues["${_cfg_template}_config_disabled"]}"

    test "$_cfg_selector_config" = "null" && _cfg_selector_config="${configTemplateValues["${_cfg_template}_config_selector_config"]}"
    test "$_cfg_selector_files" = "null" && _cfg_selector_files="${configTemplateValues["${_cfg_template}_config_selector_files"]}"
    test "$_cfg_selector_feeds" = "null" && _cfg_selector_feeds="${configTemplateValues["${_cfg_template}_config_selector_feeds"]}"
    test "$_cfg_selector_patches" = "null" && _cfg_selector_patches="${configTemplateValues["${_cfg_template}_config_selector_patches"]}"
    test "$_cfg_openwrt_rev" = "null"  && _cfg_openwrt_rev="${configTemplateValues["${_cfg_template}_config_openwrt_rev"]}"
    test "$_cfg_openwrt_variant" = "null"  && _cfg_openwrt_variant="${configTemplateValues["${_cfg_template}_config_openwrt_variant"]}"
    test "$_cfg_feeds" = "null"  && _cfg_feeds="${configTemplateValues["${_cfg_template}_config_feeds"]}"
    test "$_cfg_packages" = "null"  && _cfg_packages="${configTemplateValues["${_cfg_template}_config_packages"]}"
  fi

  # 3. check that all mandatory values are set (if no template was given in a config section, all entries
  #    must be specified)
  if [ "$_cfg_openwrt_rev" = "null" \
        -o "$_cfg_selector_config" = "null" -o "$_cfg_selector_files" = "null" \
        -o "$_cfg_selector_feeds" = "null" -o "$_cfg_selector_patches" = "null" ]; then
        echo "Error: configuration '${_cfg_name}' is not complete or there is no template specified"
        echo $entry | jq $OPT "$x"
        return 3
  fi

# echo "_cfg_type=[${_cfg_type}]"
# echo "_cfg_template=[${_cfg_template}]"
# echo "_cfg_name=[${_cfg_name}]"
# echo "_cfg_file=[${_cfg_file}]"
# echo "_cfg_disabled=[${_cfg_disabled}]"
# echo "_cfg_openwrt_rev=[${_cfg_openwrt_rev}]"
# echo "_cfg_openwrt_variant=[${_cfg_openwrt_variant}]"
# echo "_cfg_selector_config=[${_cfg_selector_config}]"
# echo "_cfg_selector_feeds=[${_cfg_selector_feeds}]"
# echo "_cfg_selector_files=[${_cfg_selector_files}]"
# echo "_cfg_selector_patches=[${_cfg_selector_patches}]"
# echo "_cfg_feeds=[${_cfg_feeds}]"
# echo "_cfg_packages=[${_cfg_packages}]"

  return 0
}

listTargets()
{
 OPT="--raw-output" # do not excape values

# └ ┌ ┐ ┘ ├ ┤ ┬ ┴ ─ │ ┼
 printf -- '┌──────────────────────────────────┬─────────┬────────────┬─────────┬──────────┬─────────┬─────────┬─────────┬──────────────────────┐\n'
 printf -- '│ %-32.32s │ %-7.7s │ %-10.10s │ %-7.7s │ %-8.8s │ %-7.7s │ %-7.7s │ %-7.7s │ %-20.20s │\n' Name Version Openwrt  Openwrt Openwrt Feeds Files Patches "Build date"
 printf -- '│ %-32.32s │ %-7.7s │ %-10.10s │ %-7.7s │ %-8.8s │ %-7.7s │ %-7.7s │ %-7.7s │ %-20.20s │\n' ""   ""      Revision Variant Selector "" "" "" ""
 printf -- '├──────────────────────────────────┼─────────┼────────────┼─────────┼──────────┼─────────┼─────────┼─────────┼──────────────────────┤\n'

 # run through all of json
 targetIdx=0
 while true
 do
  entry=$(echo "$cleanJson" | jq ".[$targetIdx]")
  targetIdx=$(( targetIdx + 1 ))

  resolveConfigValues "${entry}"; ret=$?
  # last entry
  [ "$ret" = "1" ] && break
  # is template
  [ "$ret" = "2" ] && continue

	# get firmware version
	fw_version_file="$RUN_DIR/fw-files/${_cfg_selector_files}/etc/version"
	[ -f "$fw_version_file" ] || fw_version_file="$RUN_DIR/fw-files/${_cfg_selector_files}.common/etc/version"
	fw_version="$(cat $fw_version_file)"

  # get status
  buildroot="$WORK_DIR/${_cfg_openwrt_rev:0:9}"
  test -n "${_cfg_openwrt_variant}" && buildroot="$buildroot.${_cfg_openwrt_variant}"
  _compile_status_dir="$RUN_DIR/$buildroot/${LOCAL_OUTPUT_DIR}/${COMPILE_STATUS_DIR}"
  compile_status_file="${_compile_status_dir}/${_cfg_name}-${COMPILE_STATUS_FILE_SUFFIX}"

  compile_status=""
  compile_data=""
  if [ -f "${compile_status_file}" ]; then
    eval $(cat "${compile_status_file}" | jq $OPT '"compile_data=\"\(.date)\";compile_status=\(.status)"')
  fi

  case "${compile_status}" in
    "0") cstatus="${PBC_SUCCESS}" ;;
    "1") cstatus="${PBC_ERROR}" ;;
    "2") cstatus="${PBC_RUNNING}" ;;
    *)
      # if there is another compile status code
      if [ -n "${compile_status}" ]; then
        cstatus="${C_LBLUE}${BG_WHITE}${compile_status}${C_NONE}"
      else
        cstatus="${PBC_SPACE}"
      fi
      ;;
  esac

  # overwrite if disabled
  if [ "${_cfg_disabled}" == "true" ]; then
    cstatus="${PBC_DISABLED}"
  fi

  printf  "│$cstatus %-31s │ ${list_color[${fw_version}]}%-7.7s${C_NONE} │ %-10.10s │ %-7.7s │ ${list_color[${_cfg_selector_config}]}%-8.8s${C_NONE} │ ${list_color[${_cfg_selector_files}]}%-7.7s${C_NONE} │ ${list_color[${_cfg_selector_feeds}]}%-7.7s${C_NONE} │ ${list_color[${_cfg_selector_patches}]}%-7.7s${C_NONE} │ %-20.20s │\n" "${_cfg_name}" "${fw_version}" "${_cfg_openwrt_rev:0:9}" "${_cfg_openwrt_variant}" "${_cfg_selector_config}" "${_cfg_selector_feeds}" "${_cfg_selector_files}" "${_cfg_selector_patches}" "${compile_data}"
 done

 printf -- '└──────────────────────────────────┴─────────┴────────────┴─────────┴──────────┴─────────┴─────────┴─────────┴──────────────────────┘\n'
}


listTargetsNames()
{
  echo "$cleanJson" | jq --raw-output '.[] | select(.type != "template") | .name'
}

# returns number of targets in build.json
numberOfTargets()
{
 ARG_regexTarget=$1
 [ -z "$ARG_regexTarget" ] && ARG_regexTarget='.*'

  echo "$cleanJson" | jq --raw-output "[  .[] | select(.type != \"template\")
      | select(	.name | test (\"${ARG_regexTarget}\") ) ] | length"
}

search_target()
{
  target=$1
  awk 'BEGIN {IGNORECASE=1;} /^CONFIG_TARGET_.*'$target'.*=y/{line=gsub(/^CONFIG_TARGET_.*DEVICE_/,"");print FILENAME"\t\t,"$0}' fw-configs/*/*
}

print_devices_for_target()
{
  target=$1

  targetIdx=0
  while true
  do
    entry=$(echo "$cleanJson" | jq ".[$targetIdx]")
    targetIdx=$(( targetIdx + 1 ))	# for next build loop

    resolveConfigValues "${entry}"; ret=$?
    # last entry
    [ "$ret" = "1" ] && break
    # is template
    [ "$ret" = "2" ] && continue

    # when I have a target name, then only show this.
    # when I do not have a target passt to "build.sh devices" then show all.
    if [ -n "$target" -a "$target" != "$_cfg_name" ]; then
      continue
    fi

    echo "target: [$_cfg_name] (${_cfg_selector_config})"
    grep "^CONFIG_TARGET_DEVICE.*=y" "fw-configs/${_cfg_selector_config}/${_cfg_file}"
    echo ""

    # if I had a target, then no need to run through rest
    test -n "$target" && break
  done
}

# this function checks if all firmware files are generated for selected devices for a specific target
verify_firmware_present()
{
  target=$1
  firmware_path=$2

  targetIdx=0
  while true
  do
    entry=$(echo "$cleanJson" | jq ".[$targetIdx]")
    targetIdx=$(( targetIdx + 1 ))	# for next build loop

    resolveConfigValues "${entry}"; ret=$?
    # last entry
    [ "$ret" = "1" ] && break
    # is template
    [ "$ret" = "2" ] && continue

    if [ "$target" != "$_cfg_name" ]; then
      continue
    fi

    # extract selected devices from openwrt config file and check
    # if sysupgrade file is present
    status=0
    for dev in $(grep "^CONFIG_TARGET_DEVICE.*=y" "${RUN_DIR}/fw-configs/${_cfg_selector_config}/${_cfg_file}")
    do
      # extract firmware device name part
      dev="${dev/*_DEVICE_/}"
      dev_str="${dev/=*/}"

      printf "verify firmware for: ${dev_str}: "

      p1="$(ls -1 ${firmware_path}/*${dev_str}*sysupgrade.bin 2>/dev/null)"
      p2="$(ls -1 ${firmware_path}/*${dev_str}*.img.gz 2>/dev/null)"

      if [ -n "$p1" -o -n "$p2" ]; then
        printf -- "${C_GREEN}ok${C_NONE}\n"
      else
        printf -- "${C_RED}failed${C_NONE}\n"
        status=1
      fi

    done
    return ${status};
  done
}

setup_dynamic_firmware_config()
{
  FILES="$1"
	credentials="$FILES/etc/config/credentials"

  test -f "$credentials" || return 1

  # modify registration credentials from envronment variable passed in by gitlabs
  # FF_REGISTERKEY_PREFIX is set in gitlab UI of freifunk-dresden-firmware: settings->CI/CD->Environment
  sed -i "/register_service_url/s#registerkey='#registerkey=${FF_REGISTERKEY_PREFIX//_/:}'#" $credentials

  # modify key
  [ -z "${FF_MESH_KEY}" ] && FF_MESH_KEY='custom-firmware-key'
  sed -i "/wifi_mesh_key/s#ffkey-placeholder#${FF_MESH_KEY}#" $credentials

	return 0
}

preProcessBuildJson()
{
  ignoreTemplates=$1

  # get global clean build.json
  cleanJson=$(getTargetsJson)

  if [ -z "$ignoreTemplates" ]; then
    # uses cleanJson
    echo "resolve config templates...."
    resolveTemplates
  fi
}

bash_completion()
{
  #this function must be alled "sourced" to tell bash how to complete
  # list all values that bash should complete

  ARGS="list lt list-targets watch devices search feed-revisions clean menuconfig defconfig rerun all failed"

  # add targets
  ARGS="${ARGS} $(listTargetsNames)"
  # echo "[$ARGS]"
  complete -W "${ARGS}" ./build.sh
}

usage_short()
{
  echo "Version: $SCRIPT_VERSION"
  echo "usage: $(basename $0) [options] <command | target-pattern > [clean | menuconfig | defconfig | rerun]   [-- < make params ... > ]"
}

usage()
{
  # create a simple menu
  usage_short
  cat <<EOM

 options:
   -h    docker host, if not specified environment variable 'FF_DOCKER_HOST' or 'DOCKER_HOST' is used.
         FF_DOCKER_HOST is used in favour to DOCKER_HOST. -h still has highest preference
         e.g: tcp://192.168.123.123

   -d    use docker for compiling (keep workdir)
   -D    use docker for compiling (clear workdir)
   -s    opens a shell to running docker

  commands:
   bash-completion         - adds bash completion. Must be called from same directory
                             where "build.sh" is located.
                             Example:
                               $ cd ~/projects/freifunk/firmware
                               $ source ./build.sh bash-completion

                             add an alias to your .bash_aliases
                             $ alias ff='cd ~/projects/freifunk/firmware; source ./build.sh bash-completion'

   list                    - lists all available targets
   lt | list-targets       - lists only target names for usage in IDE
   watch                   - same as 'list' but updates display
   devices [target]        - displays all selected routers for a target
   search <string>         - search specific router (target)
   feed-revisions          - displays the openwrt default feed revisions.
                             The revisions then could be set in build.json

   target-pattern          - target to build
           that are defined by build.json. use 'list' for supported targets.
           'all'                   - builds all targets
           'failed'                - builds only previously failed or not built targets
           'ramips* '              - builds all ramips targets only
           'ramips.rt305x.generic' - builds exact this target
           '*generic'              - builds all that end with generic

  flags
   clean            - cleans buildroot/bin and buildroot/build_dir (keeps toolchains)
   menuconfig       - displays configuration menu
   defconfig        - only updates configs (dependencies)
   rerun            - enables a second compilation with make option 'V=s'
                      If first make failes a second make is tried with this option
   -- make params   - all paramerters that follows are passed to make command


Devel-Notes:

 To compile a specific feed change to workdir and call something like:

     make package/feeds/ddmesh/fastd/compile -j1 V=s

EOM
}



###----------------------------------start----------------------------------------------------------


# overwrite DOCKER_HOST variable if FF_DOCKER_HOST is present. this value can still be overwritten by -h option
test -n "${FF_DOCKER_HOST}" && export DOCKER_HOST="${FF_DOCKER_HOST}"

# check if there are options
while getopts "sDdh:" arg
do
  case "$arg" in
    h)
      test -z "${OPTARG}" && echo "docker host"
      export DOCKER_HOST="${OPTARG}" # export it here, to not overwrite external possible
      ;;                                   # variable
    d)
      USE_DOCKER=true
      DOCKER_RM_WORKDIR=false
      if [ -z "$(which docker)" ]; then
        echo "Error: no docker installed"
        exit 1
      fi
      ;;
    D)
      USE_DOCKER=true
      DOCKER_RM_WORKDIR=true
      if [ -z "$(which docker)" ]; then
        echo "Error: no docker installed"
        exit 1
      fi
      ;;
    s)
      USE_DOCKER=true
      RUN_DOCKER_SHELL="1"
      if [ -z "$(which docker)" ]; then
        echo "Error: no docker installed"
        exit 1
      fi
      ;;

    \?)	exit 1	;;
  esac
done
shift $(( OPTIND - 1 ))

#for a;  do echo "arg [$a]"; done
#echo $@

if [ -z "$1" -a "$RUN_DOCKER_SHELL" != "1" ]; then
  usage
  exit 1
fi

# if docker is used, this script should be called from docker container
if $USE_DOCKER; then
  echo "Using Docker at ${DOCKER_HOST:=localhost}"
  docker_tar="$(mktemp -u).tgz"
  docker_tar=$(basename ${docker_tar})	# remove path

  # check connection
  docker info 2>/dev/null >/dev/null || {
    echo "Error: docker host not reachable"
    exit 1
  }

  # create container if it does not exisits and upload current directory
  docker inspect ${DOCKER_CONTAINER_NAME} >/dev/null 2>/dev/null || {
    echo -e "${C_CYAN}create container${C_NONE}"
    docker create -it --name ${DOCKER_CONTAINER_NAME} --user $(id -u) ${DOCKER_IMAGE}
  }
  echo -e "${C_CYAN}start container${C_NONE}"
  docker start ${DOCKER_CONTAINER_NAME}

  if [ "$RUN_DOCKER_SHELL" = "1" ]; then
    docker exec -it ${DOCKER_CONTAINER_NAME} bash
  else

    # create file to upload
    echo -e "${C_CYAN}create project archive${C_NONE}"
    tar -cz --exclude ${WORK_DIR} --exclude ${DL_DIR} --exclude ${FINAL_OUTPUT_DIR} \
        --exclude-backups --exclude-vcs --exclude-vcs-ignores \
        -f "/tmp/${docker_tar}" ./

    # upload and extract (workdir is not included)
    echo -e "${C_CYAN}copy project to container${C_NONE}"
    docker cp "/tmp/${docker_tar}" ${DOCKER_CONTAINER_NAME}:/builds/
    docker exec -it ${DOCKER_CONTAINER_NAME} sh -c "rm -rf fw-files fw-feeds fw-configs; tar -xzf ${docker_tar} && rm ${docker_tar}"
    rm /tmp/${docker_tar}

    # remove workdir from previous usage of this container (when still available)
    ${DOCKER_RM_WORKDIR} && {
      echo -e "$${C_LCYAN}remove workdir${C_NONE}"
      docker exec -it ${DOCKER_CONTAINER_NAME} rm -rf ${WORK_DIR}
    }

    docker exec -it ${DOCKER_CONTAINER_NAME} git config --global http.sslverify false

    echo -e "${C_CYAN}run build${C_NONE}"

    # need to pass target as one parameter. $@ does separate target list ("ar71xx.tiny.lowmem ath79.generic lantiq.xrx200")
    target="$1"
    shift
    docker exec -it -e FF_REGISTERKEY_PREFIX=$FF_REGISTERKEY_PREFIX ${DOCKER_CONTAINER_NAME} ./build.sh "$target" $@

    # ignore some operations for some arguments. it makes no sence to start those short commands. can be done locally
    case "$1" in
    list) ;;
    lt | list-targets) ;;
    search) ;;
    clean) ;;
    feed-revisions) ;;
    *)
      if [ "$target" = "all" ]; then
        echo -e "${C_CYAN}generate upload${C_NONE}"
        docker exec -it ${DOCKER_CONTAINER_NAME} ./gen-upload.sh all
      fi

      # create tar and copy results back
      echo -e"${C_CYAN}copy out results to [${C_YELLOW}${DOCKER_FINAL_TGZ}]${C_NONE}"

      docker exec -it ${DOCKER_CONTAINER_NAME} tar czf ${DOCKER_FINAL_TGZ} final_output
      docker cp ${DOCKER_CONTAINER_NAME}:/builds/${DOCKER_FINAL_TGZ} "${DOCKER_FINAL_TGZ}"

      # extract it in local folder
      tar xzf "${DOCKER_FINAL_TGZ}"
      rm "${DOCKER_FINAL_TGZ}"
      ;;
    esac

    # stop (keep container)
    echo -e "${C_CYAN}stop container${C_NONE}"
    docker stop -t0 ${DOCKER_CONTAINER_NAME}
  fi

  exit 0
fi

#---- process parameters -----------


targetRegex=""
case "$1" in
    bash-completion)
            printf "setting up bash_completion... "
            preProcessBuildJson true
            bash_completion
            printf "done\n"
            # this script is called "sourced", so use return instead of exit to avoid
            # closing current terminal
            return
            ;;

    list)
            preProcessBuildJson
            listTargets;
            exit 0
            ;;

    watch)
            preProcessBuildJson
            while sleep 1
            do
              view=$(listTargets)
              clear
              echo -e "$view"
              date +'%H:%M:%S / %d %h %y'
            done
            exit 0
            ;;

    lt|list-targets)
            preProcessBuildJson true
            listTargetsNames
            exit 0
            ;;

    search)
          if [ -z "$2" ]; then
            echo "Error: missing parameter"
            exit 1
          fi
          search_target $2
          exit 0
          ;;

    devices)
          preProcessBuildJson
          # if [ -z "$2" ]; then
          # 	echo "Error: missing target"
          # 	exit 1
          # fi
          print_devices_for_target $2
        #verify_firmware_present $2 $3 && echo ok || echo fehler
          exit 0
          ;;

    feed-revisions)
          echo "!!! go to openwrt build directory and look at 'feeds.conf.default'"
          exit 0
          ;;

    *)
          preProcessBuildJson

          # targets, menuconfig, rerun and make parameters are passed as argument with its parameters
          # check for "menuconfig"
          # check for "rerun"
          # check for make parameters "--"
          while [ -n "$1" ]
          do
            endLoop=0;
            arg="$1"
            shift			# prepare for next loop
            case "${arg}" in
              clean)
                      MAKE_CLEAN=1
                      endLoop=1
                    ;;
              menuconfig)
                      MENUCONFIG=1
                      endLoop=1
                      ;;
              defconfig)
                      DEFCONFIG=1
                      endLoop=1
                      ;;
              rerun)
                      REBUILD_ON_FAILURE=1
                      endLoop=1
                      ;;
              --)
                      BUILD_PARAMS=$*
                      endLoop=1
                      ;;
              all)
                      ARG_TARET_ALL=1
                      targetRegex=".*"
                      ;;
              failed)
                      ARG_CompiledFailedOnly=1
                      targetRegex=".*"
                      ;;

              *)
                # process and append target "${arg}" to targetRegex
                echo "target:${arg}"
                # replace wildcard with regex wildcard
                targetRegex="${targetRegex} ${arg//\*/.*}"
                ;;
            esac

            [ $endLoop = 1 ] && break
          done
          ;;
esac

# check of we have a targetRegex
if [ -z "$targetRegex" ]; then
  echo "Error: no target specified"
  usage_short
  exit 1
fi

#--- process targets ---
# remove invalid characters: '/','$'
chars='[/$]'
targetRegex=${targetRegex//$chars/}

# remove leading and trailing spaces
targetRegex=$(echo "${targetRegex}" | sed 's#[ 	]\+$##;s#^[ 	]\+##')

# replace any "space" with '$|^'. space can be used as separator lile '|'
# This ensures that full target names are only considered instead of processing
# targets that just start with the given name
# If wildecards are needed, user has to add them
targetRegex=$(echo "${targetRegex}" | sed 's#[ ]\+#$|^#g')

# append '$' to targetRegex, to ensure that 'ar71xx.generic.xyz' is not built
# when 'ar71xx.generic' was specified. Use 'ar71xx.generic.*' if both
# targets should be created

targetRegex="^$targetRegex\$"

echo "### target-regex:[$targetRegex] MENUCONFIG=${MENUCONFIG} DEFCONFIG=${DEFCONFIG} CLEAN=${MAKE_CLEAN} REBUILD_ON_FAILURE=${REBUILD_ON_FAILURE} BUILD_PARAMS=[${BUILD_PARAMS}]"

# prinzip:
# 1. separate each object from array and pipe it to 'select'
# 2. 'select' only let pass objects when true
# 3. .name is piped to both 'test' functions at same time.
# 4. 'not' function seams to have highere priority than 'and'. brackets are not needed, but I
#    have added those for more clarifications
#    The second 'test' outcome (true or false) are piped to 'not' and negates the output of the
#    second 'test'
# 5. first 'test' second 'test' are logical evaluated with 'and', and determines the input of
#    'select' function

# echo "$cleanJson" | jq --raw-output ".[]
#       | select(	.name |
#                       ( test (\"${targetRegex}\")  and  ( test(\"^default\") | not ) )
#               ) | .name"
# # same as first command; but creates an array from what 'select' filters, which in turn is
# # then counted by function 'length'
# echo "$cleanJson" | jq --raw-output "[ .[]
#       | select(	.name |
#                       ( test (\"${targetRegex}\")  and  ( test(\"^default\") | not ) )
#               ) ] | length"

# emtpy line needed, else tput stuff clears some. So this emtpy line is cleared
echo " "

if [ "$_TERM" = "1" ]; then
  trap clean_up_exit SIGINT SIGTERM
  trap show_progress WINCH
fi

# ---------- create directories: dl, workdir -----------
# only create top-level directories if thoses do not not
# exisist. I do not simply call 'mkdir -p'. This is because
# gitlab runner may store the content somewhere else to
# and creates a symlink to this location.
# This avoids using caching and artifacts copying between
# jobs and stages. cache and workdir are only stored on
# server where the runner is running.
# If owner of the runner doesn't setup a symlink then
# all files are stored within current directory (where build.sh
# is located)

test -L $DL_DIR || mkdir -p $DL_DIR
test -L $WORK_DIR || mkdir -p $WORK_DIR



# ------------- prepare progress bar -----------------------------------
progress_counter=0
progress_max=$(numberOfTargets "$targetRegex")

if [ $progress_max -eq 0 ]; then
   echo "no target found"
  clean_up_exit 1
fi
# progbar_char holds the current count character for each build.
# this means that each target can display a different character in progressbar to show the
# build status.
# example: |####|.....|*****|
# see variables MARK_xxx for characters

unset progbar_char_array

# ---------------- build loop, run through all targets listed in build.json -----------------
targetIdx=0
while true
do
  cd $RUN_DIR

  # read configuration from first target in build.json
  entry=$(echo "$cleanJson" | jq ".[$targetIdx]")
  targetIdx=$(( targetIdx + 1 ))	# for next build loop

  resolveConfigValues "${entry}"; ret=$?
  # last entry
  [ "$ret" = "1" ] && break
  # is template
  [ "$ret" = "2" ] && continue

  #check if configuration name matches the targetRegex (target parameter)
  # add '\' to each '|' only for sed command
  sedTargetRegex=${targetRegex//|/\\|}
  filterred=$(echo ${_cfg_name} | sed -n "/$sedTargetRegex/p")
  test -z "$filterred" && continue

  # only enable progressbar for tty
  if [ "$_TERM" = "1" ]; then
    show_progress ${_cfg_name} $progress_counter $progress_max "${progbar_char_array[@]}"
    echo ""
  fi
  # increment counter (needed also when no progressbar is displayed, because the
  # status is set despite of the usage of the progbar_char_array. This avoids
  # the need of checking every time whether the progressbar is used or not
  progress_counter=$(( $progress_counter + 1 ))

  # construct config filename
  config_file="$CONFIG_DIR/${_cfg_selector_config}/${_cfg_file}"

  # summary
  echo -e $C_GREY"----------------------------------------"$C_NONE
  echo -e $C_YELLOW"Running as user$C_NONE   : $C_BLUE$(id | awk '{print $1,$2}')"$C_NONE
  echo -e $C_YELLOW"Name$C_NONE              : $C_BLUE${_cfg_name}"$C_NONE
  echo -e $C_YELLOW"Openwrt Variant$C_NONE   : $C_BLUE${_cfg_openwrt_variant}"$C_NONE
  echo -e $C_YELLOW"Config-File$C_NONE       : $C_BLUE${config_file}"$C_NONE
  echo -e $C_GREY"----------------------------------------"$C_NONE

  # ingore disabled targets
  if [ "${_cfg_disabled}" == "true" ]; then
    progbar_char_array[$((progress_counter-1))]="${PBC_DISABLED}"
    continue
  fi

  # construct build directory name

  # use short revision because openwrt build path gets too long and
  # make for ipq40xx.generic (fritzbox 4040) will fail
  # (see git log --abbrev-commit)
  buildroot="$WORK_DIR/${_cfg_openwrt_rev:0:9}"
  test -n "${_cfg_openwrt_variant}" && buildroot="$buildroot.${_cfg_openwrt_variant}"

  _compile_status_dir="$RUN_DIR/$buildroot/${LOCAL_OUTPUT_DIR}/${COMPILE_STATUS_DIR}"
  compile_status_file="${_compile_status_dir}/${_cfg_name}-${COMPILE_STATUS_FILE_SUFFIX}"
  mkdir -p ${_compile_status_dir}

  # remove compile status (before checking for failed only)
  [ "${MAKE_CLEAN}" = "1" ] && rm -f ${compile_status_file}

  # get compile status, default is error (==1)
  compile_status=1
  if [ "$ARG_CompiledFailedOnly" = "1" ]; then
    if [ -f "${compile_status_file}" ]; then
      eval $(cat "${compile_status_file}" | jq $OPT '"compile_status=\(.status)"')
    fi
    # ignore successfull targets
    test "$compile_status" = "0" && {
      progbar_char_array[$((progress_counter-1))]="${PBC_SKIP}"
      continue;
    }
  fi

  # --- only delete after "failed-check"
  # between each target build; remove directory. at end images and packets are copied to
  # target specfic directory.
  # This is needed to avoid conflicts with packages when I have several configs that all
  # use same target/subtarget directories.
  # - reset also compile status ${compile_status_file}
  outdir="${RUN_DIR}/${buildroot}/${LOCAL_OUTPUT_DIR}/${_cfg_name}"
  rm -rf ${outdir}/*
  rm -rf ${buildroot}/bin

  write_compile_status "${_cfg_name}" "2" "${compile_status_file}"

  # progress bar: compiling
  progbar_char_array[$((progress_counter-1))]="${PBC_RUNNING}"
  show_progress ${_cfg_name} $progress_counter $progress_max "${progbar_char_array[@]}"


  openwrt_dl_dir="$DL_DIR"
  openwrt_patches_dir="$OPENWRT_PATCHES_DIR/${_cfg_selector_patches}"

  # --------- setup build root ------------------

  setup_buildroot $buildroot $_cfg_openwrt_rev $openwrt_dl_dir $openwrt_patches_dir $_cfg_selector_files

  # --------  generate feed configuration from selected config -----------
  echo -e $C_CYAN"generate feed config"$C_NONE

  # create feed config from build.json
  if [ "$_cfg_feeds" = "null" ]; then
     echo -e $C_RED"Error: no feeds specified"$C_NONE
    clean_up_exit 1
  fi

  feedConfFileName="$buildroot/feeds.conf"
cat<<EOM > $feedConfFileName
# This file is generated by build.sh from build.json
# see: https://git.openwrt.org/feed/packages.git and others

EOM

  feedIdx=0
  while true
  do
    feed=$(echo "${_cfg_feeds}" | jq ".[$feedIdx]")
    feedIdx=$(( feedIdx + 1 ))
    test "$feed" = "null" && break

    _feed_type=$(echo $feed | jq $OPT '.type')
    _feed_name=$(echo $feed | jq $OPT '.name')
    _feed_src=$(echo $feed | jq $OPT '.src')
    _feed_rev=$(echo $feed | jq $OPT '.rev')

    # for local feeds set correct absolute filename because when workdir is a symlink (like on gitlab runners),
    # relative path are note resolved correctly. Also we need to use _cfg_selector_feeds.
    # "feeds" : [
    #   {"type":"src-link", "name":"ddmesh",   "src":"" },
    #   {"type":"src-git",  "name":"packages", "src":"https://git.openwrt.org/feed/packages.git", "rev":"afea2bc"},
    #   {"type":"src-git",  "name":"routing",  "src":"https://git.openwrt.org/feed/routing.git",  "rev":"4b2b6b3"}
    # ],
    # The feed directory for "ddmesh" is directly located below firmware/feeds/<feed-selector>/
    if [ "$_feed_type" = "src-link" ]; then
      _feed_src="${RUN_DIR}/fw-feeds/${_cfg_selector_feeds}/${_feed_src}"
      _feed_rev=""	# src-link does not have a rev, because it is already in current git repo
    else
      # if we have a feed revision, then add it. "^" is a special character
      # followed by a "commit" (hash). openwrt then checks out this revision
      test "${_feed_rev}" = "null" && _feed_rev=""
      test -n "${_feed_rev}" && _feed_rev="^${_feed_rev}"
    fi

    printf "%s %s %s\n" "${_feed_type}" "${_feed_name}" "${_feed_src}${_feed_rev}"  >>$feedConfFileName

  done

  echo "------------------------------"
  echo "change to buildroot [$buildroot]"
  cd $buildroot

  if [ "$MAKE_CLEAN" = "1" ]; then
    echo -e $C_CYAN"run clean"$C_NONE
    make clean
    continue # clean next target
  fi

  # --------- update all feeds from feeds.conf (feed info) ----
  echo -e $C_CYAN"update feeds"$C_NONE
  ./scripts/feeds update -a

  echo -e $C_CYAN"install packages"$C_NONE
  echo "$_cfg_packages" | jq
  # install additional packages (can be selected via "menuconfig")
  idx=0
  while true
  do
      # use OPT to prevent jq from adding ""
    entry="$(echo ${_cfg_packages} | jq $OPT .[$idx])"
    test "$entry" = "null" && break
    idx=$(( idx + 1 ))

    echo -e "[$idx] package: [$C_GREEN${entry}$C_NONE]"
    ./scripts/feeds install ${entry}
  done

  echo -e $C_CYAN"install all packages from own local feed directory (ddmesh)"$C_NONE
  ./scripts/feeds install -a -p ddmesh

  rm -f .config		# delete previous config in case we have no $RUN_DIR/$config_file yet and want to
                  # create a new config

  DEFAULT_CONFIG="${RUN_DIR}/${CONFIG_DIR}/${_cfg_selector_config}/${CONFIG_DEFAULT_FILE}"
  if [ ! -f "${RUN_DIR}/${config_file}" ]; then
    if [ "$MENUCONFIG" = "1" ]; then
      echo -e "${C_CYAN}NO Config: use initial config${C_NONE} [${C_GREEN}${DEFAULT_CONFIG}${C_NONE}]"

      if [ ! -f ${DEFAULT_CONFIG} ]; then
        echo -e "${C_RED}ERROR: NO Default Config:${C_NONE} [${DEFAULT_CONFIG}]"
        clean_up_exit 1
      fi

      # remove any old config from build root
      rm -f .config

      # default config contains important configs that must exist before creating
      # a new config via menuconfig. this default config overwrites also some
      # important configs after running menuconfig.
      # SEE: CONFIG_VERSION_FILENAMES is not set

      # copy initial default config before firsttime "menuoconfig". this is needed
      # to get CONFIG_TARGET_PER_DEVICE_ROOTFS working. see help page in menuconfig
      cp ${DEFAULT_CONFIG} .config

    else
      # no config and no menuconfig -> continue with next target; do not create config yet.
      # it only should be down by menuconfig
      echo -e $C_CYAN"no configuration, continue with next target if any$C_NONE"
      progbar_char_array[$((progress_counter-1))]="${PBC_IGNORE}"
      continue
    fi
  else
    # copy specific config
    echo -e $C_CYAN"copy configuration$C_NONE: $C_GREEN$RUN_DIR/$config_file$C_NONE"
    cp $RUN_DIR/$config_file .config
  fi

  if [ "$MENUCONFIG" = "1" ]; then

    echo -e "${C_CYAN}run menuconfig${C_NONE}"
    make menuconfig
  fi

  # default config contains important modifications after openwrt has created a config from scratch
  # or user has enabled some unsupported features by freifunk.
  # All invalid settings are overwritten by just appending the default config.
  # see https://openwrt.org/docs/guide-developer/build-system/use-buildsystem
  # The default config is generated with those steps:
  # 1. cd workdir/buildroot
  # 2. rm .config
  # 3. unselect all unwanted configuration that should be removed from (e.g. IPV6,PPP,....)

  echo -e "${C_CYAN}post-overwrite configuration${C_NONE}: ${C_GREEN}${RUN_DIR}/${config_file}${C_NONE}"
  cat ${DEFAULT_CONFIG} >> .config
  echo -e "${C_CYAN}reprocess configuration${C_NONE}: ${C_GREEN}${RUN_DIR}/${config_file}${C_NONE}"
  make defconfig
  echo -e "${C_CYAN}copy back configuration${C_NONE}: ${C_GREEN}${RUN_DIR}/${config_file}${C_NONE}"
  cp .config ${RUN_DIR}/${config_file}

  if [ "$MENUCONFIG" = "1" ]; then
    echo ""
    clean_up_exit 0
  fi

  if [ ! "$DEFCONFIG" = "1" ]; then
    # run make command
    make clean
    echo -e $C_CYAN"time make$C_NONE $C_GREEN$BUILD_PARAMS$C_NONE"
    time -p make -j$(nproc) $BUILD_PARAMS
    error=$?
    echo "make ret: $error"

    # continue with next target in build.targets
    if [ $error -ne 0 ]; then
      global_error=1
      progbar_char_array[$((progress_counter-1))]="${PBC_ERROR}"

      echo -e $C_RED"Error: build error"$C_NONE "at target" $C_YELLOW "${_cfg_name}" $C_NONE

      if [ "$REBUILD_ON_FAILURE" = "1" ]; then
        echo -e $C_CYAN".......... rerun build with V=s ........................"$C_NONE
        time -p make $BUILD_PARAMS V=s -j1
        error=$?
        if [ $error -ne 0 ]; then
          echo -e $C_RED"Error: build error - 2nd make run reported an error"$C_NONE
          clean_up_exit 1
        fi
      fi
      # ignore error and continue with next target
      echo -e "${C_RED}Error: ignore build error${C_NONE} target and ${C_YELLOW}continue${C_NONE} with next"
      continue
    fi

    # check if we have file
    target_dir="${RUN_DIR}/${buildroot}/bin/targets"
    if [ ! -d "${target_dir}" ]; then
      echo -e "${C_RED}Error: build error - generated directory not found${C_NONE}"
      echo "     ${target_dir}"
      clean_up_exit 1
    fi

    # copy files to our own output directory
    mkdir -p ${outdir}/packages ${outdir}/images

    echo -e "${C_CYAN}copy version file${C_NONE}"
    mv ${RUN_DIR}/${buildroot}/files/etc/version ${outdir}// 2>/dev/null

    echo -e "${C_CYAN}copy packages${C_NONE} (if any)"
    mv ${RUN_DIR}/${buildroot}/bin/packages/*/* ${outdir}/packages/ 2>/dev/null

    echo -e "${C_CYAN}copy images${C_NONE}"
    mv ${RUN_DIR}/${buildroot}/bin/targets/*/*/* ${outdir}/images/

    echo -e "${C_CYAN}images created in${C_NONE} ${C_GREEN}${outdir}${C_NONE}"

    # verify presens of all images
    echo -e "${C_CYAN}verify images${C_NONE} for ${_cfg_name}"
    if ! verify_firmware_present "${_cfg_name}" "${outdir}/images"; then
      echo -e "${C_RED}Error: not all firmware images generated${C_NONE}"
      error=1
      global_error=1
      # clean_up_exit 1
    fi

    # write build status which is displayed by "build.sh list"
    echo -e $C_CYAN"write compile status to [${compile_status_file}]"$C_NONE
    write_compile_status "${_cfg_name}" "${error}" "${compile_status_file}"

    # success status
    if [ ${error} == 0 ]; then
      progbar_char_array[$((progress_counter-1))]="${PBC_SUCCESS}"
    else
      progbar_char_array[$((progress_counter-1))]="${PBC_ERROR}"
    fi
  fi # if [ ! "$DEFCONFIG" = "1" ]

done

show_progress ${_cfg_name} $progress_counter $progress_max "${progbar_char_array[@]}"
sleep 1

echo -e $C_CYAN".......... complete build finished (exitcode ${global_error})........................"$C_NONE
echo ""

clean_up_exit ${global_error}
