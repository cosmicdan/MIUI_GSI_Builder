#!/bin/bash

# Make target img script



source ./bin/common_functions.sh

checkAndMakeTmp

# Check A/B or A only build
if [ -f "./target_system/system/build.prop" ]; then
	SRC_GSI_SYSTEM="system"
else
	SRC_GSI_SYSTEM="."
fi

echo ""
echo "------------------------------------------"
echo "[i] 90_make_target_img started."
echo ""


echo "[#] Building collated file_contexts ..."
# Collate file_contexts
# skipped "./src_miui_vendor/etc/selinux/nonplat_file_contexts"
verifyFilesExist \
	"./src_miui_system/etc/selinux/plat_file_contexts" \
	"./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_file_contexts" \
	"./src_miui_vendor/etc/selinux/nonplat_file_contexts"

cat \
	"./src_miui_system/etc/selinux/plat_file_contexts" \
	"./target_system/${SRC_GSI_SYSTEM}/etc/selinux/plat_file_contexts" \
	"./src_miui_vendor/etc/selinux/nonplat_file_contexts" > "./tmp/file_contexts"

# append additionals
if [ -f "./target_patches/file_contexts.additional" ]; then
	cat "./target_patches/file_contexts.additional" >> "./tmp/file_contexts"
fi

# remove duplicate entries. There should be a better way to do this...
sort -u -k1,1 "./tmp/file_contexts" > "./tmp/file_contexts_sorted"

echo "[#] Building target_system.img ..."
"./bin/make_ext4fs" -T 0 -S "./tmp/file_contexts_sorted" -l 2600M -L / -a / -s "./target_system.img" "./target_system/"


echo ""
echo "[i] 90_make_target_img finished."
echo "------------------------------------------"
echo ""

cleanupTmp