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
bootclasspath_miui_blacklist=("com.qualcomm.qti.camera.jar" "QPerformance.jar")
	# TODO: These BOOTCLASSPATH entries are also unique to MIUI, but may be vendor specific - need to investigate:
		# /system/framework/tcmiface.jar
		# /system/framework/telephony-ext.jar
		# /system/framework/WfdCommon.jar
		# /system/framework/oem-services.jar

# prop file locations to consider for source (GSI) reading and target (MIUI) writing
prop_locations=("etc/prop.default" "build.prop")


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
		testmode)
		TESTMODE=TRUE
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
	echo "    [testmode]"
	echo "        # Do a test build, which will only copy main target_system files if the directory doesn't exist."
	echo "        # Useful for testing kitchen development changes."
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

if [ -d "./target_system" -a "${TESTMODE}" != "TRUE" ]; then
	echo "[!] A ./target_system/ folder exists."
	echo "    Aborting for safety reasons."
	exit -1
fi

if [ "${TESTMODE}" == "TRUE" ]; then
	echo "[i] Testmode enabled. Will only copy the bulk of GSI/MIUI files if target_system does not exist."
fi

checkAndMakeTmp

###############
### Copy files
###############

if [ "${TESTMODE}" != "TRUE" -o ! -d "./target_system" ]; then
	echo "[#] Creating GSI with MIUI replaced /system..."
	mkdir "./target_system"
	if [ "${TARGET}" == "ab" ]; then
		rsync -a --exclude 'system' "./src_gsi_system/" "./target_system/"
		rsync -a "src_miui_system/" "target_system/${SRC_GSI_SYSTEM}/"
		echo "[#] Replacing selinux with GSI..."
		rm -rf "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/*"
		rsync -a "./src_gsi_system/system/etc/selinux/" "./target_system/${SRC_GSI_SYSTEM}/etc/selinux/"
	else
		echo "[!] A-only build not yet supported. Aborting."
		exit -1
	fi
fi

# Debug = god-mode ADBD
if [ "${DEBUG}" == "TRUE" ]; then
	echo "[#] Insecure/root-mode ADBD patch..."
	if [ "${TARGET}" == "ab" ]; then
		sed -i --follow-symlinks 's|ro.adb.secure=.*|ro.adb.secure=0|g' "./target_system/${SRC_GSI_SYSTEM}/etc/prop.default"
		sed -i --follow-symlinks 's|ro.debuggable=.*|ro.debuggable=1|g' "./target_system/${SRC_GSI_SYSTEM}/etc/prop.default"
		sed -i --follow-symlinks 's|persist.sys.usb.config=.*|persist.sys.usb.config=adb|g' "./target_system/${SRC_GSI_SYSTEM}/etc/prop.default"
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
echo "[#] Init changes..."
verifyFilesExist "./src_miui_initramfs/init.miui.rc"
cp -af ./src_miui_initramfs/init.miui.rc ./target_system/${SRC_GSI_SYSTEM}/etc/init/init.miui.rc

echo "    [#] Parsing MIUI BOOTCLASSPATH..."
# get BOOTCLASSPATH from MIUI
bootclasspath=`cat ./src_miui_initramfs/init.environ.rc | grep -i 'export BOOTCLASSPATH ' | sed 's|^[ \t]*export BOOTCLASSPATH[ \t]*||'`

# split bootclasspath into an array
IFS=':' read -r -a bootclasspath_array <<< "${bootclasspath}"
# clear the existing bootclasspath var since we're about to rebuild it from the array
bootclasspath=""
# strip black-listed entries from bootclasspath
for bootclasspath_entry in "${bootclasspath_array[@]}"; do	
	skip=false
	for blacklist_entry in "${bootclasspath_miui_blacklist[@]}"; do
		if [ ! "${bootclasspath_entry/$blacklist_entry}" == "${bootclasspath_entry}" ] ; then
			# get the target file path for this jar
			targetJarPath="./target_system`echo ${bootclasspath_entry} | sed 's|/system/|'/${SRC_GSI_SYSTEM}/'|'`"
			rm -f ${targetJarPath}
			echo "        [i] Removed blacklisted entry and associated file: ${bootclasspath_entry}"
			skip=true
		fi
	done
	if [ "${skip}" == "false" ]; then
		if [ "${bootclasspath}" == "" ]; then
			# new
			bootclasspath="${bootclasspath_entry}"
		else
			# append
			bootclasspath="${bootclasspath}:${bootclasspath_entry}"
		fi
	fi
done

# grab MIUI's SYSTEMSERVERCLASSPATH entry too
systemserverclasspath=`cat ./src_miui_initramfs/init.environ.rc | grep -i 'export SYSTEMSERVERCLASSPATH ' | sed 's|^[ \t]*export SYSTEMSERVERCLASSPATH[ \t]*||'`

# write-out a new init.treble-environ.rc based on rebuild BOOTCLASSPATH and original SYSTEMSERVERCLASSPATH
echo "# Treble-adjusted values for MIUI GSI" > ./target_system/${SRC_GSI_SYSTEM}/etc/init/init.treble-environ.rc
cat <<EOF >>./target_system/${SRC_GSI_SYSTEM}/etc/init/init.treble-environ.rc
on init
    export BOOTCLASSPATH ${bootclasspath}
    export SYSTEMSERVERCLASSPATH ${systemserverclasspath}
EOF

echo "    [i] Wrote BOOTCLASSPATH and SYSTEMSERVERCLASSPATH to init.treble-environ.rc"



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
# Remove stuff that is (probably) not used by GSI generification. Note that usr/ is later replaced by GSI version
echo "    [#] Removing vendor-specific files..."

# random crap that GSI doesn't need
removeFromTarget \
	app/CarrierConfigure \
	app/CtRoamingSettings \
	app/SnapdragonSVA \
	app/seccamsample \
	etc/audio_policy.conf \
	etc/vold.fstab \
	etc/bluetooth/bt_profile.conf \
	etc/bluetooth/interop_database.conf \
	etc/init/init.qti.fm.rc \
	etc/permissions/qti_permissions.xml \
	lib/egl \
	lib64/egl \
	lib/modules \
	lib/rfsa \
	lib/android.hardware.biometrics.fingerprint@*.so \
	lib64/android.hardware.biometrics.fingerprint@*.so \
	lib/android.hardware.health@*.so \
	lib/android.hardware.radio.deprecated@*.so \
	lib64/android.hardware.radio.deprecated@*.so \
	lib/android.hardware.radio@*.so \
	lib64/android.hardware.radio@*.so \
	lib/android.hidl.base@*.so \
	lib64/android.hidl.base@*.so \
	lib/com.qualcomm.qti.*.so \
	lib64/com.qualcomm.qti.*.so \
	lib/vendor.qti.*.so \
	lib64/vendor.qti.*.so \
	lib/vndk-sp/android.hidl.base@*.so \
	lib64/vndk-sp/android.hidl.base@*.so \
	lib/libsensor1.so \
	lib/libsensor_reg.so \
	lib64/libsensor1.so \
	lib64/libsensor_reg.so \
	lib64/android.hardware.wifi.supplicant@*.so \
	lib64/android.hardware.wifi@*.so \
	priv-app/cit \
	priv-app/AutoTest \
	usr/
	#bin/mm-qcamera-daemon

# Qualcomm telephony	
removeFromTarget \
	bin/dpmd \
	etc/init/dpmd.rc \
	app/QtiTelephonyService \
	etc/permissions/telephonyservice.xml \
	framework/QtiTelephonyServicelibrary.jar \
	
# Qualcomm location	
removeFromTarget \
	lib/liblocationservice_jni.so \
	lib64/liblocationservice_jni.so \
	lib/libxt_native.so \
	lib64/libxt_native.so \
	priv-app/com.qualcomm.location
	
# TODO - remove anything else marked with "qti"
# TODO: there's a crapton of more libs in MIUI that don't exist in GSI, will sort through that later

# Copy unique GSI stuff
echo "    [#] Copying unique GSI files..."
rsync -a --ignore-existing "./src_gsi_system/system/bin/" "./target_system/${SRC_GSI_SYSTEM}/bin/"
rsync -a --ignore-existing "./src_gsi_system/system/etc/" "./target_system/${SRC_GSI_SYSTEM}/etc/"
rsync -a --ignore-existing "./src_gsi_system/system/lib/" "./target_system/${SRC_GSI_SYSTEM}/lib/"
rsync -a --ignore-existing "./src_gsi_system/system/lib64/" "./target_system/${SRC_GSI_SYSTEM}/lib64/"
rsync -a --ignore-existing "./src_gsi_system/system/phh/" "./target_system/${SRC_GSI_SYSTEM}/phh/"
rsync -a --ignore-existing "./src_gsi_system/system/usr/" "./target_system/${SRC_GSI_SYSTEM}/usr/"
rsync -a --ignore-existing "./src_gsi_system/system/xbin/" "./target_system/${SRC_GSI_SYSTEM}/xbin/"

echo "    [#] Replacing specific files with GSI version..."
addToTargetFromGsi \
	compatibility_matrix.xml \
	bin/keystore \
	etc/bluetooth/bt_did.conf \
	etc/init/audioserver.rc \
	etc/init/bootanim.rc
	#bin/cameraserver

# TODO: Disable cameraserver for now (broken and stops boot)
mv "./target_system/${SRC_GSI_SYSTEM}/bin/cameraserver" "./target_system/${SRC_GSI_SYSTEM}/bin/cameraserver_disabled"
	
if [ "${TARGET}" == "ab" ]; then
	echo "    [#] Additional generification for A/B devices..."
	addToTargetFromGsi \
		bin/bootctl
fi


###############
### Props
###############

echo "[#] Adding/updating props ..."
{
IFS=
echo "" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
echo "######" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
echo "# Additional for MIUI GSI" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
echo "######" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"
echo "" >> "./target_system/${SRC_GSI_SYSTEM}/${prop_locations[0]}"

# First, remove desired props listed in props.remove
echo "    [#] Removing specific props..."
if [ -f "./target_patches/props.remove" ]; then
	# sed is used here to skip over blank/empty lines
	sed '/^[ \t]*$/d' "./target_patches/props.remove" | while read -r LINE; do
		if [[ "${LINE}" == "#"* ]]; then
			# skip comments
			continue
		fi
		propKey="${LINE%=*}="
		addOrReplaceTargetProp "${propKey}"
	done
fi

# Add/replace literal props from props.additional
echo "    [#] Additional custom props..."
if [ -f "./target_patches/props.additional" ]; then
	# sed is used here to skip over blank/empty lines
	sed '/^[ \t]*$/d' "./target_patches/props.additional" | while read -r LINE; do
		if [[ "${LINE}" == "#"* ]]; then
			# skip comments
			continue
		fi
		propKey="${LINE%=*}="
		addOrReplaceTargetProp "${propKey}" "${LINE}"
	done
fi

# Merge in specified prop keys with values sourced from GSI
echo "    [#] GSI-sourced props..."
if [ -f "./target_patches/props.merge" ]; then
	# sed is used here to skip over blank/empty lines
	sed '/^[ \t]*$/d' "./target_patches/props.merge" | while read -r LINE; do
		if [[ "${LINE}" == "#"* ]]; then
			# skip comments
			continue
		fi
		propKey="${LINE%=*}="
		for propFile in "${prop_locations[@]}"; do
			propSearch=`grep ${propKey} "./src_gsi_system/${SRC_GSI_SYSTEM}/${propFile}"`
			if [ "${propSearch}" != "" ]; then
				propFound="${propSearch}"
			fi
			# don't break if found - we want to get the last found prop to try and simulate standard behavior
		done
		if [ "${propFound}" == "" ]; then
			# Error-out if the prop key wasn't found in the GSI
			echo "[!] Error - cannot find prop from GSI with key: ${propKey}"
			echo "    Aborted."
			exit -1
		else
			addOrReplaceTargetProp "${propKey}" "${propFound}"
			propFound=""
		fi
	done
fi

}




###############
### Misc. fixups
###############

echo "[#] Misc. fixups..."
# TODO: Is this necessary?
#if [ -d "./target_system/odm" ]; then
	# A/B devices only
#	rm -rf ./target_system/odm
#	ln -s /vendor ./target_system/odm
#fi

# TODO: Automate this in init script. Phh has a clever way of hiding files, e.g.:
# mount -o bind system/phh/empty /system/etc/permissions/android.hardware.consumerir.xml
# rm -rf /vendor/overlay/*

# TODO: 'can't get icon cache folder' - customized_icons is not created?



###############
### Finished
###############

echo ""
echo "[i] 01_make_target_from_src finished."
echo "------------------------------------------"
echo ""

cleanupTmp

