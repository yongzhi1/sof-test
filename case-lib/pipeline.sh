#!/bin/bash

# This function will evaluate pipeline parameter related shell code generated by
# - sof-tplgreader.py (for SOF, pipeline parameters dumped from topology)
# - sof-dump-status.py (for legacy HDA, pipeline paramters dumped from proc)
# Args: $1: SOF topology path
#       $2: Pipeline filter in string form
# Note: for legacy HDA, topology is not present, $1 will be empty.
func_pipeline_export()
{

    # function parameter check
    if [ $# -ne 2 ]; then
        die "Not enough parameters, expect two parameters: topology path and pipeline filter"
    fi

    # For legacy HDA platform, there is no topology, we have to export pipeline
    # parameters from proc file system.
    is_sof_used || {
        filter_str="$2"
        dlogi "No SOF sound card found, exporting pipeline parameters from proc file system"
        tmp_pipeline_params=$(mktemp /tmp/pipeline-params.XXXXXXXX)
        sof-dump-status.py -e "$filter_str" > "$tmp_pipeline_params" ||
            die "Failed to export pipeline parameters from proc file system"
        # shellcheck disable=SC1090
        source "$tmp_pipeline_params" || return 1
        rm "$tmp_pipeline_params"
        [ "$PIPELINE_COUNT" -ne 0 ] || die "No pipeline found from proc file system"
        return 0
    }

    # got tplg_file, verify file exist
    tplg_path=$(func_lib_get_tplg_path "$1") || {
        die "Topology $1 not found, check the TPLG environment variable or specify topology path with -t"
    }
    dlogi "$SCRIPT_NAME will use topology $tplg_path to run the test case"

    # create block option string
    local ignore=""
    if [ ${#TPLG_IGNORE_LST[@]} -ne 0 ]; then
        for key in "${!TPLG_IGNORE_LST[@]}"
        do
            dlogi "Pipeline list to ignore is specified, will ignore '$key=${TPLG_IGNORE_LST[$key]}' in test case"
            ignore=$ignore" $key:${TPLG_IGNORE_LST[$key]}"
        done
    fi

    local opt="$2"
    # In no HDMI mode, exclude HDMI pipelines
    [ -z "$NO_HDMI_MODE" ] || opt="$opt & ~pcm:HDMI"
    opt="-f '${opt}'"

    [[ "$ignore" ]] && opt="$opt -b '$ignore'"
    [[ "$SOFCARD" ]] && opt="$opt -s $SOFCARD"

    local -a pipeline_lst
    local cmd="sof-tplgreader.py $tplg_path $opt -e" line=""
    dlogi "Run command to get pipeline parameters"
    dlogc "$cmd"
    readarray -t pipeline_lst < <(eval "$cmd")
    for line in "${pipeline_lst[@]}"
    do
        eval "$line"
    done
    [[ ! "$PIPELINE_COUNT" ]] && die "Failed to parse $tplg_path, please check topology parsing command"
    [[ $PIPELINE_COUNT -eq 0 ]] && dlogw "No pipeline found with option: $opt, unable to run $SCRIPT_NAME" && exit 2
    return 0
}

func_pipeline_parse_value()
{
    local idx=$1
    local key=$2
    [[ $idx -ge $PIPELINE_COUNT ]] && echo "" && return
    local array_key='PIPELINE_'"$idx"'['"$key"']'
    eval echo "\${$array_key}" # dynmaic echo the target value of the PIPELINE
}
