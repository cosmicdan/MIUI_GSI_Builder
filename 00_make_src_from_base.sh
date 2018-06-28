#!/bin/bash

# Make src from base script
#
# This script is for unpacking base MIUI and GSI images. It only needs to be done once when new base firmwares are provided. Various 
# parts of this script require sudo elevation. 
#
# All script tasks are as follows:
# 1) Unpack file system image files from ./base_{miui|gsi}/ to ./src_{miui|gsi}_{system|vendor}
#    - Will detect and unpack brotli, .dat and sparse image files if necessary.
# 2) Backup the file ACL tree for extracted image files, then recursive mode 777 on extracted trees (for ease of development and research)
#    - The backed-up ACL list is used to restore ACL in the target image
# 3) Unpack miui boot.img initramfs (RAMDisk) to ./src_miui_initramfs/ and do the ACL backup and chmod stuff to it as in #2
#
# After this is done, you can delete any extra left-over files in ./base_{miui|gsi}/ if you want the space back. Just be sure to track your changes
# in the extracted ./src_* folders; these are expected to remain unmodified and original from source when building; ./target_patches/ are where
# the additional target changes should live.
# 



source ./bin/common_functions.sh

echo ""
echo "------------------------------------------"
echo "[i] 00_make_src_from_base started."
echo ""

checkAndMakeTmp

# Unpack filesystem images
for baseSuffix in "miui" "gsi"; do
	if [ -d "./base_${baseSuffix}" ]; then
		for imageName in "system" "vendor"; do
			echo "[#] Processing ${imageName} ..."
			
			# unpack brotli image
			if [ -f "./base_${baseSuffix}/${imageName}.new.dat.br" ]; then
				if [ ! -f "./base_${baseSuffix}/${imageName}.new.dat" ]; then
					echo "    [#] Decompressing ./base_${baseSuffix}/${imageName}.new.dat.br to ./base_${baseSuffix}/${imageName}.new.dat ..."
					brotli -d -o "./base_${baseSuffix}/${imageName}.new.dat" "./base_${baseSuffix}/${imageName}.new.dat.br"
				else
					echo "    [i] Skipping brotli decompress since .dat file already exists"
				fi
			fi
			
			# unpack new.dat to img
			if [ -f "./base_${baseSuffix}/${imageName}.new.dat" -a -f "./base_${baseSuffix}/${imageName}.transfer.list" ]; then
				if [ ! -f "./base_${baseSuffix}/${imageName}.img" ]; then
					echo "    [#] Converting ./base_${baseSuffix}/${imageName}.new.dat to ./base_${baseSuffix}/${imageName}.img ..."
					./bin/sdat2img.py "./base_${baseSuffix}/${imageName}.transfer.list" "./base_${baseSuffix}/${imageName}.new.dat" "./base_${baseSuffix}/${imageName}.img" >/dev/null
				else
					echo "    [i] Skipping new.dat to img conversion since .img file already exists"
				fi
			fi
			
			# mount and extract the images
			if [ ! -d "./tmp_${baseSuffix}_${imageName}" ]; then
				if [ -f "./base_${baseSuffix}/${imageName}.img" ]; then
					# Check if sparse img, convert if so
					sparse_magic=`hexdump -e '"%02x"' -n 4 "./base_${baseSuffix}/${imageName}.img"`
					if [ "$sparse_magic" = "ed26ff3a" ]; then
						echo "    [#] Sparse image detected, converting to raw image..."
						mv "./base_${baseSuffix}/${imageName}.img" "./base_${baseSuffix}/${imageName}.simg"
						simg2img "./base_${baseSuffix}/${imageName}.simg" "./base_${baseSuffix}/${imageName}.img"
					fi
					
					if [ ! -d "./src_${baseSuffix}_${imageName}" ]; then
						echo "    [#] About to mount ./base_${baseSuffix}/${imageName}.img to ./tmp_${baseSuffix}_${imageName} [sudo mount required]"
						mkdir "./tmp_${baseSuffix}_${imageName}"
						sudo mount -t ext4 -o loop "./base_${baseSuffix}/${imageName}.img" "./tmp_${baseSuffix}_${imageName}"
						if [ $? -eq 0 ]; then
							echo "        [#] Copying contents of ./tmp_${baseSuffix}_${imageName} to ./src_${baseSuffix}_${imageName} [sudo rsync required]"
							mkdir "./src_${baseSuffix}_${imageName}"
							sudo rsync -a "./tmp_${baseSuffix}_${imageName}/" "./src_${baseSuffix}_${imageName}/"
							echo "        [#] About to unmount ./tmp_${baseSuffix}_${imageName} [sudo umount required]"
							sudo umount -f "./tmp_${baseSuffix}_${imageName}"
							if [ $? -eq 0 ]; then
								rm -d "./tmp_${baseSuffix}_${imageName}"
							else
								echo "            [!] Failed to umount ./tmp_${baseSuffix}_${imageName}. Please do so manually, and delete the directory after."
							fi
							# create facl
							echo "        [#] Creating ACL list at ./src_${baseSuffix}_metadata/${imageName}.acl [sudo getfacl required]..."
							if [ ! -d "./src_${baseSuffix}_metadata" ]; then
								mkdir "./src_${baseSuffix}_metadata"
							fi
							if [ -f "./src_${baseSuffix}_metadata/${imageName}.acl" ]; then
								rm "./src_${baseSuffix}_metadata/${imageName}.acl"
							fi
							cd "./src_${baseSuffix}_${imageName}/"
							sudo getfacl -R . > "../src_${baseSuffix}_metadata/${imageName}.acl"
							echo "        [#] Setting mode 777 recursive to ./src_${baseSuffix}_${imageName}/ [sudo chmod required]..."
							sudo chmod -R 777 .
							cd ..
						else
							echo "        [!] Mount failed. Skipping."
						fi
					else
						echo "    [i] ./src_${baseSuffix}_${imageName} already exists, skipping img extraction."
					fi
				fi
			else
				echo "    [!] Warning - ./tmp_${baseSuffix}_${imageName} already exists. Skipping mount and extract of ./base_${baseSuffix}/${imageName}.img."
			fi
		done
	else
		echo "[!] Warning - ./base_${baseSuffix} does not exist. Nothing to do."
	fi
done

# Unpack initramfs from boot.img
if [ -f "./base_miui/boot.img" ]; then
	if [ ! -d "./src_miui_initramfs" ]; then
		echo "[#] Unpacking initramfs from ./base_miui/boot.img [sudo required]..."
		mkdir "./tmp/bootimg"
		./bin/unpackbootimg --input "./base_miui/boot.img" --output "./tmp/bootimg/" >/dev/null
		mkdir "./src_miui_initramfs"
		cd "./src_miui_initramfs"
		sudo gzip -dcq "../tmp/bootimg/boot.img-ramdisk.gz" | sudo cpio -i -d --no-absolute-filenames >/dev/null
		# also backup facl and chmod
		if [ ! -d "../src_miui_metadata" ]; then
			mkdir "../src_miui_metadata"
		fi
		if [ -f "../src_miui_metadata/initramfs.acl" ]; then
			rm "../src_miui_metadata/initramfs.acl"
		fi
		echo "    [#] Creating ACL list at ./src_miui_metadata/initramfs.acl [sudo getfacl required]..."
		sudo getfacl -R . > "../src_miui_metadata/initramfs.acl"
		echo "    [#] Setting mode 777 recursive to ./src_miui_initramfs/ [sudo chmod required]..."
		sudo chmod -R 777 .
		cd ..
	else
		echo "[i] ./src_miui_initramfs already exists, skipping boot.img ramdisk unpack."
	fi
else
	echo "[!] Warning - ./base_miui/boot.img does not exist (needed for initramfs)."
fi

echo ""
echo "[i] 00_make_src_from_base finished."
echo "------------------------------------------"
echo ""

cleanupTmp
