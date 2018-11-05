#!/bin/bash -eu
#
# Author: edward.hope-morley@canonical.com
#
# Description: Use this tool to generate a Juju (2.x) native-format bundle e.g.
#
#     Xenial + Queens UCA: ./generate-bundle.sh --series xenial --release queens
#
#     Bionic (Queens) Proposed: ./generate-bundle.sh --series bionic --pocket proposed
#
#     Bionic + Stein UCA: ./generate-bundle.sh --release stein
#
#
series=bionic
series_provided=false
release=
pocket=
template=
path=
params_path=
bundle_name=
replay=false
run_command=false
declare -a overlays=()
declare -A lts=( [trusty]=icehouse
                 [xenial]=mitaka
                 [bionic]=queens )

. `dirname $0`/helpers.sh

while (($# > 0))
do
    case "$1" in
        --overlay)
            overlays+=( $2 )
            shift
            ;;
        --path)
            path=$2
            shift
            ;;
        --series)
            series=$2
            series_provided=true
            shift
            ;;
        --release)
            release=$2
            shift
            ;;
        --pocket)
            # archive pocket e.g. proposed
            pocket=$2
            shift
            ;;
        --template)
            template=$2
            shift
            ;;
        --bundle-params)
            # parameters passed by custom generators
            params_path=$2
            shift
            ;;
        --name)
            # give bundle set a name and store under named dir
            bundle_name=$2
            shift
            ;;
        --replay)
            # replay the last recorded command if exists
            replay=true
            ;;
        --run)
            # deploy bundle once generated
            run_command=true
            ;;
        -h|--help)
            _usage
            exit 0
            ;;
        *)
            echo "ERROR: invalid input '$1'"
            _usage
            exit 1
            ;;
    esac
    shift
done

[ -z "$template" ] || [ -z "$path" ] && \
    { echo "ERROR: no template provided with --template"; exit 1; }

ltsmatch ()
{
    [ -z "$release" ] && return 0
    for s in ${!lts[@]}; do
        [ "$s" = "$1" ] && [ "${lts[$s]}" = "$2" ] && return 0
    done
    return 1
}

# Replay ingores any args and just print the previously generated command
subdir="/${bundle_name}"
[ -n "${bundle_name}" ] || subdir=''
bundles_dir=`dirname $path`/b$subdir
mkdir -p $bundles_dir

finish ()
{
if $replay; then
    target=${bundles_dir}/command
    echo -e "INFO: replaying last known command (from $target)\n"
    [ -e "$target" ] || { echo "ERROR: $target does not exist"; exit 1; }
fi
echo "Command to deploy:"
cat ${bundles_dir}/command
if $run_command; then
    eval `cat ${bundles_dir}/command`
fi
$replay && exit 0
}
$replay && finish

if [ -n "$release" ] && ! ltsmatch $series $release; then
    declare -a idx=( ${!lts[@]} )
    i=${#idx[@]}
    _series=${idx[$((--i))]}
    series_plus_one=$_series
    while ! [[ "$release" > "${lts[$_series]}" ]] && ((i>=0)); do
        s=${idx[$((i))]}
        if ! $series_provided && [ "${lts[$s]}" = "$release" ]; then
            _series=$s
            break
        fi
        series_plus_one=$s
        _series=${idx[$((--i))]}
    done
    # ensure correct series
    if $series_provided; then
        if ! [ "$series" = "$_series" ]; then
            echo "Series auto-corrected from '$series' to '$_series'"
        fi
    fi
    series=$_series
else
    release=${lts[$series]} 
fi

source=''
if ! ltsmatch $series $release ; then
  source="cloud:${series}-${release}"
fi

if [ -n "$pocket" ]; then
  if [ -n "$source" ]; then
    source="${source}\/${pocket}"
  else
    source="$pocket";
  fi
fi

os_origin=$source
[ "$os_origin" = "proposed" ] && os_origin="distro-proposed"

render () {
# generic replacements
sed -i -e "s/__SERIES__/$series/g" \
       -e "s/__OS_ORIGIN__/$os_origin/g" \
       -e "s/__SOURCE__/$source/g" $1

# service-specific replacements
if [ -n "$params_path" ]; then
    eval `cat $params_path` $1
fi
}

fout=`mktemp -d`/`basename $template| sed 's/.template//'`
cp $template $fout
render $fout

mv $fout $bundles_dir
target=${series}-$release
[ -z "$pocket" ] || target=${target}-$pocket
result=$bundles_dir/`basename $fout`

# remove duplicate overlays
declare -a _overlays=()
declare -A overlay_dedup=()
if ((${#overlays[@]})); then
    mkdir -p $bundles_dir/o
    echo "Created $target bundle and overlays:"
    for overlay in ${overlays[@]}; do
        [ "${overlay_dedup[$overlay]:-null}" = "null" ] || continue
        cp overlays/$overlay $bundles_dir/o
        _overlays+=( --overlay $bundles_dir/o/$overlay )
        render $bundles_dir/o/$overlay
        overlay_dedup[$overlay]=true
        echo " + $overlay"
    done
    echo ""
else
    echo -e "Created $target bundle\n"
fi

echo -e "juju deploy ${result} ${_overlays[@]:-}\n" > ${bundles_dir}/command
finish