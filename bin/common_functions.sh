#!/bin/bash

# Common functions shared by multiple scripts

checkAndMakeTmp() {
	if [ -d "./tmp" ]; then
		echo "[!] An old ./tmp/ folder exists. This is usually cleaned up; there may be WIP changes here or an error previously occured."
		echo "    Aborting for safety reasons. Please delete or move ./tmp/ when you're sure you want to discard it."
		exit -1
	fi
	mkdir ./tmp
}

cleanupTmp() {
	rm -rf "./tmp"
}

verifyFilesExist() {
	for filepath in "$@"; do
		if [ ! -f "${filepath}" -a ! -d "${filepath}" ]; then
			echo "[!] Error - cannot find file/directory '${filepath}'"
			echo "    Aborted."
			exit -1
		fi
	done
}

addToTargetFromGsi() {
	for gsiPath in "$@"; do
		verifyFilesExist "./src_gsi_system/${SRC_GSI_SYSTEM}/${gsiPath}"
		cp -af "./src_gsi_system/${SRC_GSI_SYSTEM}/${gsiPath}" "./target_system/${SRC_GSI_SYSTEM}/${gsiPath}"
	done
}

removeFromTarget() {
	for targetFilePath in "$@"; do
		(
		shopt -s extglob # expands any wildcards passed in
		rm -r ./target_system/${SRC_GSI_SYSTEM}/${targetFilePath}
		)
	done
}

# Thanks to "Nominal Animal" @ linuxquestions.org
getEscapedVarForSed() {
	 # start with the original pattern
    escaped="$1"

    # escape all backslashes first
    escaped="${escaped//\\/\\\\}"

    # escape slashes
    escaped="${escaped//\//\\/}"

    # escape asterisks
    escaped="${escaped//\*/\\*}"

    # escape full stops
    escaped="${escaped//./\\.}"    

    # escape [ and ]
    escaped="${escaped//\[/\\[}"
    escaped="${escaped//\[/\\]}"

    # escape ^ and $
    escaped="${escaped//^/\\^}"
    escaped="${escaped//\$/\\\$}"

    # remove newlines
    escaped="${escaped//[$'\n']/}"

    # Now, "$escape" should be safe as part of a normal sed pattern.
    # Note that it is NOT safe if the -r option is used.
	echo "${escaped}"
}

# Arguments to pass-in:
# - prop keyname with trailing =
# - full replacement prop keyname=value string. If empty, the prop will be commented-out instead
addOrReplaceTargetProp() {
	propKey="$1"
	propKeyValueNew="$2"
	propReplaced=FALSE
	for propFile in "${prop_locations[@]}"; do
		if grep -q ${propKey} "./target_system/${SRC_GSI_SYSTEM}/${propFile}"; then
			propKeyEscaped=`getEscapedVarForSed "${propKey}"`
			if [ "${propKeyValueNew}" == "" ]; then
				# missing second parameter = comment-out instead of replace
				sed -i "/${propKeyEscaped}/s/^/#/g" "./target_system/${SRC_GSI_SYSTEM}/${propFile}"
			else
				replacementEscaped=`getEscapedVarForSed "${propKeyValueNew}"`
				sed -i "s|${propKeyEscaped}.*|${replacementEscaped}|g" "./target_system/${SRC_GSI_SYSTEM}/${propFile}"
			fi
			propReplaced=TRUE
			# don't break - we want to find and replace all occurances (in every prop file)
		fi
	done
	if [ "${propReplaced}" == "FALSE" ]; then
		if [ "${propKeyValueNew}" == "" ]; then
			# missing second parameter = comment-out instead of replace
			echo "    [!] Property was not found for removal, continuing anyway: ${propKey}"
		else
			# prop wasn't found, add it
			echo "${propKeyValueNew}" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
		fi
	fi
}