# Updating the AMD kexts

RyzenStatus ships the two kexts it needs in the `Kexts` folder of the disk image: `AMDRyzenCPUPowerManagement.kext` and `SMCAMDProcessor.kext`. Always replace them as a pair, from the same release as the app. The app also runs with an older pair, but then Hardware Validation reports the driver version, and features that need the newer kext stay off (the idle clock limit needs 3.41.0 or later).

## 1. Keep a copy of the EFI that boots today

Find your EFI partition with `diskutil list` (on most Macs it is `disk0s1`), mount it, and copy the whole `EFI` folder outside it, for example to the Desktop or to a USB stick:

```bash
sudo diskutil mount disk0s1
cp -R /Volumes/EFI/EFI ~/Desktop/EFI-backup
```

## 2. Replace the two kexts

Open the disk image's `Kexts` folder and drag both bundles into `/Volumes/EFI/EFI/OC/Kexts`, replacing the old ones. Leave every other kext alone, including the GPU kexts and `AMDCCDScheduler.kext` if you use them.

Keep the folder names as they are. OpenCore loads only the kexts listed under `Kernel › Add` in `config.plist`, and each entry's `BundlePath` must name a folder that is really there: if it points at a missing folder, OpenCore stops at boot. An extra copy under another name is ignored, so a backup in the same folder is harmless.

## 3. Restart and check what loaded

```bash
kmutil showloaded | grep -E 'AMDRyzen|SMCAMD'
```

Both lines should show the new version, for example `(3.41.0)`. In RyzenStatus, Hardware Validation's kext version row should pass. If it still shows the old version, the old kext is the one OpenCore loaded: check that you copied into the EFI you boot from.

## 4. If the Mac does not boot

Boot from the OpenCore USB you installed with (or any USB with a working EFI) and pick your macOS disk. That OpenCore uses the USB's own kexts, so macOS starts with the old pair. Then mount the internal EFI again, move the new `EFI` folder aside and put your copy back:

```bash
sudo diskutil mount disk0s1
mv /Volumes/EFI/EFI /Volumes/EFI/EFI-new
cp -R ~/Desktop/EFI-backup /Volumes/EFI/EFI
```

Restart. Without a USB that boots, the copy from step 1 is your only way back, so keep one before every update.
