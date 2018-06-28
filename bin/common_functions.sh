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