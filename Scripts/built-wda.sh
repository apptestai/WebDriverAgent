#!/bin/bash

readonly PROGNAME=`basename "$0"`
readonly PROGDIR=`dirname "$0"`
readonly RESIGN_TOOL=/opt/apps/ios-sdk/platform-tools/resign.sh
readonly XCODEBUILD=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild

usage() {
	cat <<- EOF
	USAGE: ${PROGNAME}

		Building WebDriverAgent

	    OPTIONS:
            -x xcconfig file
            -p project directory
            -d directory where build derived data will go (default: ${PROGDIR}/DerivedData/)

            -h show this help
            -v verbose

	    Examples:
	        ${PROGNAME} -x apptestai.xcconfig -p ${PROGDIR}  -d ${PROGDIR}/DerivedData/WDA

	EOF
}

check_errs()
{
	if [ $? -ne 0 ]; then
	    echo "Encountered an error, aborting!" >&2
	    exit 1
	fi
}

error() {
    local str="$1"
    echo "ERROR: ${str}"
    echo
}

verbose() {
    local str="$1"
    if [ "${VERBOSE}" = "true" ]; then
        echo "${str}"
    fi
}


while getopts "x:d:j:p:hv" OPTION; do
    case ${OPTION} in
        x) readonly XCONFIG=${OPTARG}
            ;;
        d) DERIVED_DATA_PATH=${OPTARG}
            ;;
        p) readonly PROJECT=${OPTARG}
            ;;
        h) usage
           exit 0
            ;;
        v) readonly VERBOSE=true
            ;;
        \?) echo "Invalid option: -${OPTARG}" >&2
            ;;
        :) echo "Option -${OPTARG} requires an argument." >&2
            exit 1
            ;;
    esac
done


if [ ! -n "${PROJECT}" ]; then
    error "Path to project is missing (-i)"
    usage
    exit 1
fi

if [ ! -n "${XCONFIG}" ]; then
    error "Path to xcconfig is missing (-i)"
    usage
    exit 1
fi

if [ ! -f "${XCONFIG}" ]; then
    error "Could not find xcconfig ${XCONFIG}"
    exit 1
fi

if [ ! -n "${DERIVED_DATA_PATH}" ]; then
	DERIVED_DATA_PATH="${PROGDIR}/DerivedData/"
fi

verbose "\nbuild-for-testing ..."
$XCODEBUILD build-for-testing -project ${PROJECT}/WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner -xcconfig ${XCONFIG} -derivedDataPath "${DERIVED_DATA_PATH}" -destination generic/platform=iOS
