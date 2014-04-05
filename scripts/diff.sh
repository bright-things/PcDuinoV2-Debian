#!/bin/bash
# creates update package
IMAGEPATH="/home/cubie/image/output"
IMAGE1="CTDebian_1.8_vga.raw"
IMAGE2="CTDebian_1.7_vga.raw"
mkdir -p $IMAGEPATH/a
mkdir -p $IMAGEPATH/b
mkdir -p $IMAGEPATH/c
losetup -o 1048576 /dev/loop0 $IMAGE1
losetup -o 1048576 /dev/loop1 $IMAGE2
mount /dev/loop0 $IMAGEPATH/a
mount /dev/loop1 $IMAGEPATH/b

cd $IMAGEPATH/a

find . -type f | while read filename
do
   if [ ! -f "$IMAGEPATH/b/$filename" ]; then
        cp --parents "$filename" $IMAGEPATH/c
      continue
   fi
   diff "$filename" "$IMAGEPATH/b/$filename" 
   if [[ "$?" == "1" ]]; then
        # File exists but is different so copy changed file
        cp --parents $filename $IMAGEPATH/c
   fi
done

umount $IMAGEPATH/a
umount $IMAGEPATH/b
losetup -d /dev/loop0
losetup -d /dev/loop1

cd $IMAGEPATH/c
zip update.zip *