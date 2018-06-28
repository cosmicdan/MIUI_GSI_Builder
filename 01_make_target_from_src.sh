#!/bin/bash

# Make target from src script
#
# This script is for creating the MIUI GSI target from extracted src folders.
#
# All script tasks are as follows:

# TODO: A-only targets



source ./bin/common_functions.sh



###############
### Config
###############

# Entries in MIUI BOOTCLASSPATH that should be skipped
#bootclasspath_miui_blacklist=("com.qualcomm.qti.camera.jar" "QPerformance.jar")



###############
### Get arguments
###############

# Defaults
DEBUG=TRUE
TARGET=

POSITIONAL=()
while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
		-t|--target)
		# target selection (e.g. ab)
		TARGET="$2"
		shift
		shift
		;;
		user)
		DEBUG=FALSE
		shift # past argument
		;;
		*)    # unknown option
		POSITIONAL+=("$1") # save it in an array for later
		shift # past argument
		;;
	esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# For extra unrecognized arguments
#if [[ -n $1 ]]; then
    
#fi

# Show usage if -t wasnn't specified
echo ""
if [ "${TARGET}" != "ab" -a "${TARGET}" != "a" ]; then
	echo "[i] Usage for 01_make_target_from_src.sh:"
	echo "    -t|--target ab|a"
	echo "        # Specify target type"
	echo "    [user]"
	echo "        # Do non-debug build. Leave omitted for the default debug."
	echo ""
	exit -1
fi



###############
### Verify arguments
###############

if [ "${DEBUG}" == "FALSE" ]; then
	echo "[!] User build requested but currently unsupported."
	echo ""
	exit -1
fi

if [ "${TARGET}" == "ab" ]; then
	SRC_GSI_SYSTEM="system"
fi

if [ "${TARGET}" == "a" ]; then
	SRC_GSI_SYSTEM="."
fi

if [ "${SRC_GSI_SYSTEM}" == "" ]; then
	echo "[!] Unsupported target type requested - '${TARGET}'"
	echo ""
	exit -1
fi


###############
### Build environment checks
###############

echo ""
echo "------------------------------------------"
echo "[i] 01_make_target_from_src started."
echo ""

if [ -d "./target_system" ]; then
	echo "[!] A ./target_system/ folder exists."
	echo "    Aborting for safety reasons."
	exit -1
fi

checkAndMakeTmp

###############
### Copy files
###############

echo "[#] Creating GSI with MIUI replaced /system..."
mkdir "./target_system"
if [ "${TARGET}" == "ab" ]; then
	rsync -a --exclude 'system' "./src_gsi_system/" "./target_system/"
	rsync -a "src_miui_system/" "target_system/system/"
	# Add unique libs from GSI (mostly HAL/VNDK stuff)
	echo "[#] Copying unique GSI libs..."
	rsync -a --ignore-existing "./src_gsi_system/system/lib/" "./target_system/system/lib/"
	rsync -a --ignore-existing "./src_gsi_system/system/lib64/" "./target_system/system/lib64/"
	echo "[#] Replacing selinux with GSI..."
	rm -rf "./target_system/system/etc/selinux/*"
	rsync -a "./src_gsi_system/system/etc/selinux/" "./target_system/system/etc/selinux/"
else
	echo "[!] A-only build not yet supported. Aborting."
	exit -1
fi

# Debug = god-mode ADBD
if [ "${DEBUG}" == "TRUE" ]; then
	echo "[#] Insecure/root-mode ADBD patch..."
	if [ "${TARGET}" == "ab" ]; then
		sed -i --follow-symlinks 's|ro.adb.secure=.*|ro.adb.secure=0|' "./target_system/default.prop"
		sed -i --follow-symlinks 's|ro.debuggable=.*|ro.debuggable=1|' "./target_system/default.prop"
		sed -i --follow-symlinks 's|persist.sys.usb.config=.*|persist.sys.usb.config=adb|' "./target_system/default.prop"
	#else
		# ?
	fi
	sed -i --follow-symlinks 's|ro.adb.secure=.*|ro.adb.secure=0|' "./target_system/${SRC_GSI_SYSTEM}/build.prop"
	# 'God-mode' adbd (allows root daemon on user-builds)
	cp -af "./target_patches/adbd_godmode" "./target_system/${SRC_GSI_SYSTEM}/bin/adbd"
fi

###############
### Init
###############

# TODO: Parse properly and only do what's needed? Some of the miui services seem to be hardware specific, but I am not sure yet.
# Also may need seclabel changes
echo "[#] Init changes..."
verifyFilesExist "./src_miui_initramfs/init.miui.rc"
cp -af ./src_miui_initramfs/init.miui.rc ./target_system/${SRC_GSI_SYSTEM}/etc/init/init.miui.rc
# TODO: An A-only compatible version. Use the treble-environ template from GSI
cp -af ./src_miui_initramfs/init.environ.rc ./target_system/init.environ.rc



###############
### SELinux
###############

# Note - we always cat MIUI's policy first so it can take preference when duplicates exist

echo "[#] Building SELinux policy..."
# plat_file_contexts
cat "./src_miui_system/etc/selinux/plat_file_contexts" "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_file_contexts" > "./tmp/plat_file_contexts_joined"
sort -u -k1,1 "./tmp/plat_file_contexts_joined" > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_file_contexts"
# plat_property_contexts
cat "./src_miui_system/etc/selinux/plat_property_contexts" "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_property_contexts" > "./tmp/plat_property_contexts_joined"
sort -u -k1,1 "./tmp/plat_property_contexts_joined" > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_property_contexts"
# plat_seapp_contexts
cp -af "./src_miui_system/etc/selinux/plat_seapp_contexts" "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_seapp_contexts"
# plat_service_contexts
cat "./src_miui_system/etc/selinux/plat_service_contexts" "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_service_contexts" > "./tmp/plat_service_contexts_joined"
sort -u -k1,1 "./tmp/plat_service_contexts_joined" > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_service_contexts"

###########
# This is all disabled. We can't modify cil's at all for whatever reason; my kernel just freaks out and kicks to fastboot. So we are stuck on permissive for now.
# So instead we add/replace any-ol' seclabel (see "seclabel injection" below). This will cause a lot of denials of course, which is why we need permissive; but init will refuse to start any service if a label is not set/mapped so is necessary.

# mapping/27.0.cil
#cat "./src_miui_system/etc/selinux/mapping/27.0.cil" "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/mapping/27.0.cil" > "./tmp/27.0.cil_joined"
#sort -u "./tmp/27.0.cil_joined" > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/mapping/27.0.cil"

# plat_sepolicy.cil
# There will be some duplicate attributes here, but it still works so good enough, thanks to Phh for the tip.
# MIUI-unique entries will be added to the end (order preserved). Thanks to this guy: https://stackoverflow.com/a/20639730/1767892
#cat "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_sepolicy.cil" "./src_miui_system/etc/selinux/plat_sepolicy.cil" > "./tmp/plat_sepolicy.cil_joined"
#cat -n "./tmp/plat_sepolicy.cil_joined" | sort -uk2 | sort -nk1 | cut -f2- > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_sepolicy.cil"

# Regen sha
#cat \
#	"./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_sepolicy.cil" \
#	"./target_system/${SRC_GSI_SYSTEM}/etc/selinux/mapping/27.0.cil" \
#	| sha256sum | cut -d' ' -f1 > "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_and_mapping_sepolicy.cil.sha256"

###########

# seclabel injections
echo "    [#] Scanning for missing/orphaned init service SELinux labels..."
for rcFile in "./target_system/${SRC_GSI_SYSTEM}/etc/init"/*; do
	# loop over all init scripts
	#echo "        [#] ${rcFile}..."
	{
	IFS=
	# delete any previous parsed rc script
	rm -f "./tmp/rcFileNew"
	# copy the new file, but add a couple newlines to the end (fixes detection for single-service rc scripts files, and also files that don't end with an empty newline)
	cp -af "${rcFile}" "./tmp/rcFileOld"
	printf "\n\n" >> "./tmp/rcFileOld"
	cat "./tmp/rcFileOld" | while read -r LINE; do
		#echo "$LINE"
		if [[ "$(echo "${LINE}" | awk '{ print $1 }')" == "service" ]]; then
			# we've found a service declaration line, get the mapping token...
			servicePath="`echo "${LINE}" | awk '{ print $3 }'`"
			# Get service name just for log output
			serviceName="`echo "${LINE}" | awk '{ print $2 }'`"
			#echo "            [i] Service path: ${servicePath}"
			# Output line unmodified and continue reading next lines
			echo "${LINE}" >> "./tmp/rcFileNew"
		elif [ "${servicePath}" != "" ]; then
			# we're currently inside a service declaration
			if [[ "$(echo "${LINE}" | awk '{ print $1 }')" == "seclabel" ]]; then
				# current service has a custom seclabel set, set the seclabel
				seclabel="${LINE}"
				#echo "                [i] Seclabel manually specified: ${seclabel}"
				# Don't write out this line (yet)
			elif [ "${LINE}" == "" ]; then
			#elif [[ ${LINE} == *[^[:space:]]* ]]; then
				# empty line (or whitespace only) = end of service declaration
				#echo "            [#] Service declaration end"
				if [ "${seclabel}" == "" ]; then
					# No seclabel in the service declaration; look for it in plat_file_contexts
					servicePathEscaped=${servicePath//./\\\\\.}
					seclabel=`cat "./src_gsi_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_file_contexts" | grep "^${servicePathEscaped}" | awk '{ print $2 }'`
					#if [ "${seclabel}" != "" ]; then
					#	echo "            [i] Found seclabel in plat_file_contexts: ${seclabel}"
					#else
					#	echo "            [!] No seclabel in plat_file_contexts found"
					#fi
				fi
				mappingExists=FALSE
				if [ "${seclabel}" != "" ]; then
					# we have the seclabel, now try to find it in the mappings
					mappingToken="`echo "${seclabel}" | awk -F":" '{print $3}'`"
					if grep -q '^(typeattributeset .*(.*'${mappingToken}'.*))' "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/mapping/27.0.cil"; then
						# typeattributeset found in 27.0.cil
						#echo "                [i] ... Existing mapping found, no seclabel injection necessary."
						mappingExists=TRUE
					elif grep -q '^(typeattributeset .*(.*'${mappingToken}'.*))' "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_sepolicy.cil"; then
						# typeattributeset found in plat_sepolicy.cil
						#echo "                [i] ... Existing mapping found, no seclabel injection necessary."
						mappingExists=TRUE
					fi
				fi
				
				if [ "${mappingExists}" == "FALSE" ]; then
					# no existing mapping in cil, write a new seclabel
					seclabel="seclabel u:r:shell:s0"
					echo "    ${seclabel}" >> "./tmp/rcFileNew"
					#echo "                [i] No mapping found. Injected dummy seclabel entry: ${seclabel}"
					echo "      [i] Added/replaced seclabel for ${serviceName}"
				fi
				
				# write-out the empty line
				echo "" >> "./tmp/rcFileNew"

				# clear vars for next run
				serviceName=""
				servicePath=""
				mappingToken=""
				seclabel=""
			else
				# write-out original service attribute
				echo "${LINE}" >> "./tmp/rcFileNew"
			fi
		else
			# non-interesting line, just write it out
			echo "${LINE}" >> "./tmp/rcFileNew"
		fi
	done
	}
	# copy the rebuilt rcFile
	cp -af "./tmp/rcFileNew" "${rcFile}"
done



###############
### Generification
###############

echo "[#] Generification..."
# Copy GSI stuff, replacing where necessary
addToTargetFromGsi \
	bin/keystore \
	bin/cameraserver

if [ "${TARGET}" == "ab" ]; then
	echo "    [#] Additional generification for A/B devices..."
	addToTargetFromGsi \
		bin/bootctl
fi



###############
### Props
###############

# TODO: make this automated:
# 1) Build an array of all props that exist in target
# 2) Find unique ones from MIUI /vendor and add them in
#
#if [ -f "./target_patches/prop.default.additional" ]; then
#	cat "./target_patches/prop.default.additional" >> "./target_system/${SRC_GSI_SYSTEM}/etc/prop.default"
#fi



###############
### Misc. fixups
###############

# Remove vendor-specific stuff
echo "[#] Removing vendor-specific files..."
removeFromTarget \
	etc/permissions/qti_permissions.xml

echo "[#] Misc. fixups..."
# TODO: Is this necessary?
#if [ -d "./target_system/odm" ]; then
	# A/B devices only
#	rm -rf ./target_system/odm
#	ln -s /vendor ./target_system/odm
#fi

# TODO: How to exclude this manually?
# IDEA 1) Bind-mount an empty folder to this folder on startup to "hide" the contents?
# IDEA 2) Hex-edit libs that reference the path? Last resort...
# rm -rf /vendor/overlay/*

# TODO: Need to manually mkdir /data/miui/ (I think? Maybe something post-boot will do it)
# 	- Also, 'can't get icon cache folder' - customized_icons is not created.

###############
### Finished
###############

echo ""
echo "[i] 01_make_target_from_src finished."
echo "------------------------------------------"
echo ""

cleanupTmp

