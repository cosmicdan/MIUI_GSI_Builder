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
		if [ ! -f "${filepath}" ]; then
			echo "[!] Error - cannot find file '${filepath}'"
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
		rm -rf "./target_system/${SRC_GSI_SYSTEM}/${targetFilePath}"
	done
}